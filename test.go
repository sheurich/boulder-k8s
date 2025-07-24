package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// runCommands executes a list of commands. It stops and returns an error if any
// command fails.
func runCommands(commands [][]string) error {
	for _, args := range commands {
		fmt.Println("+", strings.Join(args, " "))
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("error running command %q: %w", strings.Join(args, " "), err)
		}
	}
	return nil
}

// runCommandsIgnoringErrors executes a list of commands, ignoring errors. It is
// intended for cleanup operations.
func runCommandsIgnoringErrors(commands [][]string) {
	for _, args := range commands {
		fmt.Println("+", strings.Join(args, " "))
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			fmt.Fprintf(os.Stderr, "Error during cleanup command %q: %v\n", strings.Join(args, " "), err)
		}
	}
}

func testMain() int {
	mainCommands := [][]string{
		{"hack/provision-kind.sh"},
		{"docker", "build", "--file=boulder.dockerfile", "--tag=boulder:local", "."},
		{"kind", "load", "docker-image", "boulder:local", "--name", "boulder-k8s"},
		{"helm", "install", "boulder", "charts/boulder", "--wait", "--set", "image.tag=local", "--set", "image.repository=boulder"},
		{"helm", "test", "boulder", "--logs"},
	}

	cleanupCommands := [][]string{
		{"helm", "uninstall", "boulder"},
		{"kind", "delete", "cluster", "--name", "boulder-k8s"},
	}

	defer func() {
		fmt.Println("---")
		fmt.Println("Cleaning up resources...")
		runCommandsIgnoringErrors(cleanupCommands)
	}()

	if err := runCommands(mainCommands); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		return 1
	}

	return 0
}

func main() {
	os.Exit(testMain())
}
