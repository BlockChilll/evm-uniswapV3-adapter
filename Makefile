ifneq (,$(wildcard .env))
	include .env
	export
endif

.PHONY: format
format:
	forge fmt

.PHONY: format-check
format-check:
	forge fmt --check

.PHONY: test
test:
	forge test

.PHONY: build
build:
	forge build
	
.PHONY: deploy-adapter
deploy-adapter:
	echo "Deploying adapter"
	forge script script/DeployAdapter.s.sol:DeployAdapter --broadcast -vvv --private-key $(KEY) --rpc-url $(RPC_URL) --sig "run(address,address,address,address)" $(FACTORY) $(NONFUNGIBLE_POSITION_MANAGER) $(SWAP_ROUTER) $(QUOTER)



