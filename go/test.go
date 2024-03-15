package main

import "flag"
import "fmt"

func main() {
	var ip string
	flag.StringVar(&ip, "ip", "127.0.0.1", "a IP address")

	flag.Parse()
	fmt.Println("SIP address is: ", ip)
}

