all    :; dapp build
clean  :; dapp clean
test   :; dapp --use solc:0.6.11 test -v
deploy :; dapp create Keg
