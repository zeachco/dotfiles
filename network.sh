# Kill all processes that match the given name. ie: `killname webpack` will kill all running webpack instances
killname() {
  sudo kill -9 $(ps -e | grep $1 | awk '{print $1}')
}

ipp () {
  dig +short myip.opendns.com @resolver1.opendns.com
}

ipl () {
  ifconfig | grep broadcast | awk '{print $2}'
}