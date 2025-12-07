# rbx-client-relay

a relay client server for roblox

# Description

An event-driven poller and relay client for roblox that interacts with [rbx-relay](https://github.com/boxyfour/rbx-relay).

# Features

This module handles:

* registering roblox servers with rbx-relay
* long polling for commands
* heartbeats to update server statistics
* re-registering & server downtime detector
* running callbacks when commands are received
* self cleanup & deletion

## prerequisites

You must have both [rbx-relay](https://github.com/boxyfour/rbx-relay) and [rbx-bot-relay](https://github.com/boxyfour/rbx-bot-relay) installed and running.

Your game must also have "Allow HTTP Requests" enabled under "Security" in "Game Settings".

## usage

### Rojo

If you're using Rojo, you can either ~~import the module through wally, or~~ (will be done in the future) clone the repository, and move src/poller/ into your desired packages folder.

Then, you can require the module and use it like any other class! Look at some of the examples to see how you can use the module effectively.

### Studio

Download the RBXM from the [releases](https://github.com/boxyfour/rbx-client-relay/releases) tab, and drag it into your game,
Then, you can require the module and use it like any other class! Look at some of the examples to see how you can use the module effectively.

## Important

### Issues

If there are any issues you'd like to report, you can create an issue [here](https://github.com/boxyfour/rbx-client-relay/issues). Before doing that, though, please go through the following [common issues](https://github.com/boxyfour/rbx-relay?tab=readme-ov-file#important) you might have.