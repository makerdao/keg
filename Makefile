all    :; dapp build
clean  :; dapp clean
test   :; dapp --use solc:0.5.12 test --rpc -v
deploy :; dapp create Keg
