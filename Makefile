-include .env.local
.EXPORT_ALL_VARIABLES:

PROTOCOL?=compound
NETWORK?=eth-mainnet

FOUNDRY_SRC=contracts/${PROTOCOL}/
FOUNDRY_TEST=test-foundry/${PROTOCOL}/
FOUNDRY_REMAPPINGS=@config/=config/${NETWORK}/${PROTOCOL}/
FOUNDRY_ETH_RPC_URL?=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}

ifeq (${NETWORK}, eth-mainnet)
  FOUNDRY_CHAIN_ID=1
  FOUNDRY_FORK_BLOCK_NUMBER=14292587
endif

ifeq (${NETWORK}, polygon-mainnet)
  FOUNDRY_CHAIN_ID=137
  FOUNDRY_FORK_BLOCK_NUMBER=22116728

  ifeq (${PROTOCOL}, aave-v3)
    FOUNDRY_FORK_BLOCK_NUMBER=29116728
    FOUNDRY_CONTRACT_PATTERN_INVERSE=(Fees|IncentivesVault|Rewards)
  endif
endif

ifeq (${NETWORK}, avalanche-mainnet)
  FOUNDRY_CHAIN_ID=43114
  FOUNDRY_ETH_RPC_URL=https://api.avax.network/ext/bc/C/rpc
  FOUNDRY_FORK_BLOCK_NUMBER=12675271

  ifeq (${PROTOCOL}, aave-v3)
    FOUNDRY_FORK_BLOCK_NUMBER=15675271
  endif
else
endif

ifneq (, $(filter ${NETWORK}, ropsten rinkeby))
  FOUNDRY_ETH_RPC_URL=https://${NETWORK}.infura.io/v3/${INFURA_PROJECT_ID}
endif


install:
	@yarn
	@foundryup
	@git submodule update --init --recursive

	@chmod +x ./scripts/**/*.sh

deploy:
	./scripts/${PROTOCOL}/deploy.sh

initialize:
	./scripts/${PROTOCOL}/initialize.sh

create-market:
	./scripts/create-market.sh

ci:
	@forge test -vv --gas-report --no-match-test testFuzz

test:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv --no-match-test testFuzz

test-ansi:
	@echo Running all ${PROTOCOL} tests on ${NETWORK}
	@forge test -vv --no-match-test testFuzz > trace.ansi

coverage:
	@echo Create coverage report for ${PROTOCOL} tests on ${NETWORK}
	@forge coverage --no-match-test testFuzz

coverage-lcov:
	@echo Create coverage lcov for ${PROTOCOL} tests on ${NETWORK}
	@forge coverage --report lcov --no-match-test testFuzz

fuzz:
	$(eval FOUNDRY_TEST=test-foundry/fuzzing/${PROTOCOL}/)
	@echo Running all ${PROTOCOL} fuzzing tests on ${NETWORK}
	@forge test -vv

gas-report:
	@echo Creating gas consumption report for ${PROTOCOL} on ${NETWORK}
	@forge test -vvv --gas-report > gas_report.ansi

test-common:
	@echo Running all common tests on ${NETWORK}
	@forge test -vvv -c test-foundry/common

contract-% c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv/$*.t.sol --match-contract $*

ansi-c-%:
	@echo Running tests for contract $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv/$*.t.sol --match-contract $* > trace.ansi

single-% s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvv --match-test $*

ansi-s-%:
	@echo Running single test $* of ${PROTOCOL} on ${NETWORK}
	@forge test -vvvvv --match-test $* > trace.ansi

config:
	@forge config


.PHONY: test config common foundry
