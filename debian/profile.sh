#!/bin/bash

wifi() {
	lspci -nnk | grep -iA2 net
}
