all    :; dapp build
clean  :; dapp clean
test   :; dapp --use solc:0.5.15 test --rpc -v
deploy :; dapp create Keg
