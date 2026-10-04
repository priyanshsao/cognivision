package main

import (
	"context"
	"os/signal"
	"syscall"

	"github.com/cognivision/gateway"
	"github.com/sirupsen/logrus"
)

func main() {
	logrus.SetLevel(logrus.DebugLevel)
	// Starts a watcher goroutine that watches for defined signals.
	// when interrupted with the signal it cancels the context.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	// stop is a cleanup function maybe for cleaning up the watcher goroutine,
	// it is not responsible for cancelling the ctx.
	defer stop()

	gw := gateway.NewGateway(ctx, ":8080", "localhost:6379")

	if err := gw.Start(ctx); err != nil {
		logrus.Errorf("gateway stopped: %v", err)
	}
}
