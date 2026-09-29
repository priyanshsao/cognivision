package database

import (
	"context"
	"encoding/json"
	"time"

	"github.com/cognivision/gateway/types"
	"github.com/redis/go-redis/v9"
	"github.com/sirupsen/logrus"
)

const IMAGE_KEY = "IMAGE:LATEST"
const REQUEST_STREAM = "REQUEST"
const RESULT_STREAM = "RESULT"
const IMAGE_EXPIRY_TIME = 1*time.Minute

// Db is the database which is used for storing key:val pairs
// and for streaming images to all the models
type Db struct {
	// addr represents address of the database. 
	addr string
	// client represents the database client with which we are connected.
	// Using this we can perform operations on the database.
	client *redis.Client
}

// NewDb returns new Database object.
func NewDb(addr string) *Db {
	db := new(Db)
	db.addr = addr

	return db
}

// Connect is used for creating connection with db client.
func (db *Db) Connect(ctx context.Context) error {
	clientOpts := new(redis.Options)
	clientOpts.Addr = db.addr

	// create a new redis client with options
	db.client = redis.NewClient(clientOpts)

	// Create a child ctx from the parent(main func ctx).
	// Why are we doing this, because main ctx only cancels when
	// we interrupt with SIGINT SIGTERM, 
	// if in worst case, redis is unavailable then ping func will block
	// the main goroutine forever until program is stopped.
	// So we create another ctx with 5s timeout, so even if something is wrong,
	// this will return in 5s atmost.
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	// why cancel when already timeout,
	// cancel() releases internal resources like timers etc.
	// which ctx was using.
	defer cancel()

	// try for 5s then return if no response.
	return db.client.Ping(pingCtx).Err()
}

// Addr returns the address of database client.
func (db *Db) Addr() string {
	
	return db.addr
}

// Disconnect closes the connection with db client.
func (db *Db) Disconnect() error {
	if db.client != nil {
		return db.client.Close()
	}
	return nil
}

// set is used to store a (key:value) type data in the database. 
func (db *Db) Set(ctx context.Context, key string, img []byte) error {
	
	return db.client.Set(ctx, key, img, IMAGE_EXPIRY_TIME).Err()
}

// Delete is used to delete the (key:value) type data from the database.
func (db *Db) Delete(ctx context.Context, key string) error {

	err := db.client.Del(ctx, key).Err()
	if err != nil {
		logrus.Debugf("unable to delete %s from database: %v", key, err)
		return err
	}

	return nil
}

// PushToStream pushes data to the given stream.
func (db *Db) PushToStrem(ctx context.Context, req *types.Request) (string, error) {
	payload, err := json.Marshal(req)
	if err != nil {
		return "", err
	}

	args := new(redis.XAddArgs)
	args.Stream = REQUEST_STREAM
	args.Values = map[string]interface{}{"request": payload}

	id, err := db.client.XAdd(ctx, args).Result()
	if err != nil {
		logrus.Debugf("unable to push to stream: %v", err)
	}

	logrus.Debugf("wrote %d bytes to stream.", len(payload))

	return id, err
}

// PullFromStream returns a channel which will eventually contain
// the decoded results from stream.
func (db *Db) PullFromStream(ctx context.Context) <-chan *types.InferenceResult {
	out := make(chan *types.InferenceResult)

	go readResult(ctx, db, out)

	return out
}

// readResult continiously reads from result stream until the ctx is cancelled.
// If the result message is invalid it skips it.
// Sends the decoded result to 'out' channel.
func readResult(ctx context.Context, db *Db,  out chan *types.InferenceResult) {
	defer close(out)

	// Start from the latest.
	LAST_ID := "$"

	for {
		select {
		
		// If main program stops return immediately 
		case <-ctx.Done():
			logrus.Debug("context cancelled, stopping reader.")
			return
		default:
			// otherwise continue

		}

		args := new(redis.XReadArgs)
		args.Streams = []string{RESULT_STREAM, LAST_ID}
		args.Block = 5 * time.Second
		args.Count = 50

		streams, err := db.client.XRead(ctx, args).Result()
		if err == redis.Nil {
			// no new entries within the block, so retry
			continue
		}

		if err != nil {
			if ctx.Err() != nil {
				// Shutdown if main context cancelled 
				logrus.Debugf("unable to read from stream: %v", err)
				return
			}

			logrus.Debugf("unable to read from result stream: %v", err)
			
			// Wait for some time for results to arrive.
			time.Sleep(time.Second)
			continue
		}

		for _, stream := range streams {
			for _, msg := range stream.Messages {
				// msg.Values is of map[string] interface,
				// so go has no idea of which type of data it is,
				// therefore we tell go that it is of string type. 
				rawResult, ok := msg.Values["result"].(string)
				
				// If ok is false means the particular message is not of string.
				// Better to skip this. 
				if !ok {
					continue
				}

				r := new(types.InferenceResult)

				if err := json.Unmarshal([]byte(rawResult), r); err != nil {
					logrus.Debugf("unabled to unmarshal result: %v", err)
					
					// Skip
					continue
				}
				
				logrus.Debugf("recieved result with id: %v", r.ID)
				// Add the pointer to 'out' channel, 
				// so whoever is reading can read from it.
				// MAYBE: As of now this will block until the reader reads the message.
				out <- r

				// Set this id as the last read ID.
				LAST_ID = msg.ID
				logrus.Debugf("last seen is updated to id: %v", msg.ID)
			}
		}
	}
}