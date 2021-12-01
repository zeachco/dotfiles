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

update_declarative_forms_in_playground() {
  dev cd declarative-forms
  yarn build && cp -r ./build ../declarative-forms-playground/node_modules/@shopify/declarative-forms/
  cd -
}