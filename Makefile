-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil size

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install openzeppelin/openzeppelin-contracts@v5.0.2 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

size:; forge build --sizes

snapshot :; forge snapshot

format :; forge fmt

coverage :; forge coverage

coverage-report :; forge coverage --report lcov && genhtml lcov.info -o coverage && cd coverage && python3 -m http.server 8000

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network mainnet,$(ARGS)),--network mainnet)
	NETWORK_ARGS := --rpc-url $(MAINNET_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

estimate: 
	@forge script script/DeployRare24.s.sol:DeployRare24 --rpc-url $(MAINNET_RPC_URL) -vvvv

deploy:
	@forge script script/DeployRare24.s.sol:DeployRare24 $(NETWORK_ARGS)

deploy-market:
	@forge script script/DeployMarketplace.s.sol:DeployMarketplace $(NETWORK_ARGS)