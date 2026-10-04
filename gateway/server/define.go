package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"sync"

	"github.com/cognivision/gateway/types"
	"github.com/gorilla/websocket"
	"github.com/sirupsen/logrus"
)

// ClientRequestHandler would be invoqued for each data requested by
// socket client
type ClientRequestHandler func(ctx context.Context, c *Client, data []byte)

// Client stores the client connection
type Client struct {
	// conn is the actual connection
	conn *websocket.Conn
	// buffer is the channel for all the messages that
	// needed to send to the client
	// why buffer because there are multiple go routines running
	// so to ensure a sequal message flow
	buffer chan []byte
	// closed when client is removed
	done chan struct{}
}

type Server struct {
	// port stores the port where server is running.
	port string

	// upgrader object used for upgrading the http connection
	// to the websocket by calling upgrader.Upgrade().
	upgrader websocket.Upgrader

	// mu is used for ensuring safe and race free read/write
	// operations to Server.clients map.
	mu sync.RWMutex

	// clients stores all the active and connected clients
	clients map[*Client]struct{}

	// handler is the function that should be called when client sends request,
	// the reason it is a property because that function needs access to db,
	// which only the parent gateway has, so we define the function in gateway,
	// and then we send it through this and use here.
	handler ClientRequestHandler

	ctx context.Context
}

// NewServer takes port and returns new server object with upgrader that allows all connections.
func NewServer(port string) *Server {

	s := new(Server)
	s.port = port
	s.upgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
	s.clients = make(map[*Client]struct{})

	return s
}

// newClient creates a client from given connection
// and stores it.
func (s *Server) newClient(conn *websocket.Conn) *Client {
	c := new(Client)
	c.conn = conn
	c.buffer = make(chan []byte, 16)
	c.done = make(chan struct{})

	s.storeClient(c)
	return c
}

// Write writes data to the buffer of the client.
func (s *Server) Write(c *Client, r *types.Result) error {
	payload, err := json.Marshal(r)
	if err != nil {
		logrus.Debugf("unable to marshal result: %v", err)
		return err
	}

	select {
	// this generally blocks if no one to read from channel
	// but select falls down to default when it blocks.
	case c.buffer <- payload:
	// I don't think as of now this will ever get executed.
	case <-c.done:
		return errors.New("client disconnected")
	default:
		logrus.Debugf("client buffer is full dropping result: %s", r.ID)
	}

	return nil
}

// storeClient stores the client in the list of active clients.
func (s *Server) storeClient(c *Client) {
	// hold the lock first
	s.mu.Lock()
	// unhold the lock when done
	defer s.mu.Unlock()

	s.clients[c] = struct{}{}
}

// removeClient removes the client from the active client list.
func (s *Server) removeClient(c *Client) {
	// hold the lock first
	s.mu.Lock()
	// unhold the lock when done
	defer s.mu.Unlock()

	if _, ok := s.clients[c]; ok {
		delete(s.clients, c)
		logrus.Debugf("removing client. buffer length: %d", len(c.buffer))
		close(c.done)
	}
}

// readPipe reads from connection
// until an error occurs
func (c *Client) read(ctx context.Context, handler ClientRequestHandler) {
	defer c.conn.Close()

	for {
		_, data, err := c.conn.ReadMessage() // TODO: use msgType here
		if err != nil {
			logrus.Debugf("unable to continue reading from client: %v", err)
			return
		}

		logrus.Debugf("recieved %d bytes from client.", len(data))

		handler(ctx, c, data)
	}
}

func (c *Client) write() {
	defer c.conn.Close()

	for {
		select {
		case data := <-c.buffer:
			if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
				return
			}
			logrus.Debugf("wrote %d bytes to client.", len(data))

		case <-c.done:
			return
		}
	}
}

func (s *Server) upgradeConn(w http.ResponseWriter, r *http.Request) {
	logrus.Infof("client detected: %s %s from %s (%s)", r.Method, r.URL.Path, r.RemoteAddr, r.UserAgent())

	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		logrus.Debugf("unable to upgrade client request to socket: %v", err)
		return
	}

	// create a new client from the new websocket connection
	c := s.newClient(conn)
	// remove when this handling is done
	defer s.removeClient(c)

	go c.write()
	c.read(s.ctx, s.handler)
}

// Start starts the http server on port,
// then upgrades to a websocket on address: 'host:port/gateway'.
func (s *Server) Start(ctx context.Context, handler ClientRequestHandler) error {
	s.handler = handler
	s.ctx = ctx

	mux := http.NewServeMux()
	mux.HandleFunc("/gateway", s.upgradeConn)

	httpServer := new(http.Server)
	httpServer.Addr = s.port
	httpServer.Handler = mux

	// If program exits, this goroutine shuts the server gracefully.
	go func() {
		<-ctx.Done()
		httpServer.Close()
		logrus.Info("HTTP server closed gracefully.")
	}()

	logrus.Infof("server listening on localhost%s", s.port)

	// This blocks the main goroutine.
	// When SIGINT or SIGTERM interrupts,
	// the above helper goroutine closes the server.
	err := httpServer.ListenAndServe()

	// This runs when server is closed gracefully.
	if err == http.ErrServerClosed {
		return nil
	}

	// Otherwise log the error.
	logrus.Debugf("unintended server shutdown: %v", err)

	return err
}
