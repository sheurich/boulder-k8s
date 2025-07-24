package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func main() {
	commands := [][]string{
		{"docker", "build", "--file=boulder.dockerfile", "--tag=boulder:latest", "."},
		{"docker", "run", "boulder:latest", "--version"},
	}

	for _, args := range commands {
		fmt.Println("+", strings.Join(args, " "))
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
	}
}
