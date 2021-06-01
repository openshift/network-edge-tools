package main

import (
	"log"
	"net"
)

func resolve() {
	var addrs []*net.SRV
	_, addrs, err := net.LookupSRV("http", "tcp", "headless-test")
	if err != nil {
		log.Printf("%+v", err)
	}

	log.Printf("%+v\n", addrs)
	for _, addr := range addrs {
		log.Printf("%+v\n", addr)
	}
}

func main() {
	resolve()
}
