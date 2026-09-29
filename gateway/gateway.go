package gateway

import (
	"context"
	"encoding/json"
	"os"
	"sync"
	"time"

	"github.com/cognivision/gateway/database"
	"github.com/cognivision/gateway/interpreter"
	"github.com/cognivision/gateway/server"
	"github.com/cognivision/gateway/types"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

type Gateway struct {
	// server represents the http server.
	server *server.Server
	// db represents the database which is used for streaming and storage.
	db 	   *database.Db
	
	interpreter	*interpreter.Ipt

	// mu is used for avoiding race conditions when functions access pending map.
	mu 	   sync.Mutex
	// pending stores the current processing client request's id with its client
	// so that when result is ready it can send to the client.
	pending map[string]*server.Client
}

// NewGateway takes server and database address and returns new gateway object.
func NewGateway(ctx context.Context, serverPort string, dbAddr string) *Gateway {
	gw := new(Gateway)
	gw.server = server.NewServer(serverPort)
	gw.db = database.NewDb(dbAddr)
	ipt, err := interpreter.NewIpt(ctx, os.Getenv("GEMINI_API_KEY"))
	if err != nil {
		logrus.Debugf("unable to create interpreter: %v", err)
	}
	gw.interpreter = ipt
	gw.pending = make(map[string]*server.Client)
	
	return gw
}

func (gw *Gateway) Start(ctx context.Context) error {
	// connect to database
	if err := gw.db.Connect(ctx); err != nil {
		return err
	}
	logrus.Infof("connected to database on: %s", gw.db.Addr())
	
	defer func ()  {
		gw.db.Disconnect()
		logrus.Info("database disconnected successfully.")
	}()

	// covers the second half cycle
	// reads data from inference server 
	// and then writes to client.
	go gw.readResults(ctx)

	// Covers the first half of the pipeline
	// reads data from client and then streams to
	// models.
	return gw.server.Start(ctx, gw.readAndPush)
}

func (gw *Gateway) readAndPush(ctx context.Context, c *server.Client, data []byte) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	cr := new(types.ClientRequest)
	
	if err := json.Unmarshal(data, cr); err != nil {
		logrus.Debugf("unable to unmarshal client request: %v", err)
		return
	}

	// Todo: For now this is fine, we want some simpler and shorter id's.
	key := uuid.NewString()[:8]

	if err := gw.db.Set(ctx, key, cr.Img); err != nil {
		logrus.Debugf("unable to store image: %v", err)
		return
	}

	gw.registerPending(key, c)

	req := new(types.Request)
	req.ID = key
	req.Prompt = cr.Prompt

	if _, err := gw.db.PushToStrem(ctx, req); err != nil {
		logrus.Debugf("unable to push request to stream: %v", err)
		gw.popPending(key)
		return
	}
}

// readResults reads results from stream,
// and writes to the respected client.
func (gw *Gateway) readResults(ctx context.Context) {
	resultChan := gw.db.PullFromStream(ctx)

	for r := range resultChan {
		
		// Remove the id from pending map.
		c, ok := gw.popPending(r.ID)

		// If ID is not in the pending map, skip it.
		if !ok {
			logrus.Debugf("cannot find result with id: %v", r.ID)
			continue
		}

		jsonRes, err := json.Marshal(r.Result)
		if err != nil {
			logrus.Debugf("unable to marshal result: %v", err)
		}

		summary, detail, err := gw.interpreter.Interpret(ctx, string(jsonRes), r.Prompt)
		if err != nil {
			logrus.Debugf("interpret problem: %v", err)
		}

		// Todo: this is where i think we add the processing server
		// which takes the result and provides the final result.
		// for now we create a dummy result
		result := new(types.Result)

		result.ID = r.ID
		result.Summary = summary + "\n" + detail
		result.Img = r.Img
		result.Inference = r.Result
		result.Time = 0
		result.Date = "2000"

		if err := gw.server.Write(c, result); err != nil {
			logrus.Errorf("unable to write to client: %v", err)
		}

		go gw.db.Delete(ctx, result.ID)
	}
}

func (gw *Gateway) registerPending(id string, c *server.Client) {
	gw.mu.Lock()
	defer gw.mu.Unlock()

	gw.pending[id] = c
}

// popPending helds the lock and deletes the message with given Id.
// If pending is already in use it blocks until the lock is released.
func (gw *Gateway) popPending(id string) (*server.Client, bool) {
	// Waits if lock is in use.
	gw.mu.Lock()
	// Unlock when done.
	defer gw.mu.Unlock()

	// Extract the client with the given ID.
	c, ok := gw.pending[id]
	if ok {
		delete(gw.pending, id)
		logrus.Debugf("result removed from pending, id: %v", id)
	}

	return c, ok
}