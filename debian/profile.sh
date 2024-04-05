#!/bin/env sh

wifi() {
    lspci -nnk | grep -iA2 net
}
