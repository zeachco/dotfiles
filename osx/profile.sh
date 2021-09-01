#!/bin/env bash

xcode_kill() {
  sudo rm -rf $(xcode-select -print-path)
  xcode-select --install
}

brightness 1

outside() {
  brightness 1
  sleep 10
  outside
}