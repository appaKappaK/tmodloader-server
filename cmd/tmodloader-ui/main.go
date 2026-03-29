package main

import (
	"log"
	"os"

	"github.com/appaKappaK/tmodloader-server/internal/controlroom"
)

func main() {
	baseDir, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}

	if err := controlroom.Run(baseDir); err != nil {
		log.Fatal(err)
	}
}
