-include .env.local
.EXPORT_ALL_VARIABLES:

PROTOCOL?=compound
NETWORK?=eth-mainnet

FOUNDRY_PROFILE?=${PROTOCOL}
FOUNDRY_REMAPPINGS?=@config/=config/${NETWORK}/${PROTOCOL}/
FOUNDRY_PRIVATE_KEY?=${DEPLOYER_PRIVATE_KEY}

ifneq (${NETWORK}, avalanche-mainnet)
  FOUNDRY_ETH_RPC_URL?=https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}
endif


install:
	@yarn
	@foundryup
	@git submodule update --init --recursive

	@chmod +x ./scripts/**/*.sh

deploy:
	@echo Deploying Morpho-${PROTOCOL} on ${NETWORK}
	./scripts/${PROTOCOL}/deploy.sh

initialize:
	@echo Initializing Morpho-${PROTOCOL} on "${NETWORK}"
	./scripts/${PROTOCOL}/initialize.sh

create-market:
	@echo Creating market on Morpho-${PROTOCOL} on "${NETWORK}"
	./scripts/${PROTOCOL}/create-market.sh

anvil:
	@echo Starting fork of "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}"
	@anvil --fork-url ${FOUNDRY_ETH_RPC_URL} --fork-block-number "${FOUNDRY_FORK_BLOCK_NUMBER}"

script-%:
	@echo Running script $* of Morpho-${PROTOCOL} on "${NETWORK}" with script mode: ${SMODE}
	@forge script scripts/${PROTOCOL}/$*.s.sol:$* --broadcast -vvvv

ci:
	@forge test -vv

ci-upgrade:
	@FOUNDRY_TEST=test-foundry/prod/${PROTOCOL} FOUNDRY_FUZZ_RUNS=256 forge test -vv --match-contract TestUpgrade

test:
	@echo Running all Morpho-${PROTOCOL} tests on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test -vv | tee trace.ansi

test-prod:
	@echo Running all Morpho-${PROTOCOL} production tests on "${NETWORK}" with seed "${FOUNDRY_FUZZ_SEED}"
	@FOUNDRY_TEST=test-foundry/prod/${PROTOCOL} FOUNDRY_FUZZ_RUNS=256 forge test -vv --no-match-contract TestUpgrade | tee trace.ansi

test-upgrade:
	@echo Running all Morpho-${PROTOCOL} upgrade tests on "${NETWORK}" with seed "${FOUNDRY_FUZZ_SEED}"
	@FOUNDRY_TEST=test-foundry/prod/${PROTOCOL} FOUNDRY_FUZZ_RUNS=256 forge test -vv --match-contract TestUpgrade | tee trace.ansi

test-common:
	@echo Running all common tests on "${NETWORK}"
	@FOUNDRY_TEST=test-foundry/common forge test -vvv | tee trace.ansi

coverage:
	@echo Create lcov coverage report for Morpho-${PROTOCOL} tests on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge coverage --report lcov
	@lcov --remove lcov.info -o lcov.info "test-foundry/*"

lcov-html:
	@echo Transforming the lcov coverage report into html
	@genhtml lcov.info -o coverage

gas-report:
	@echo Creating gas report for Morpho-${PROTOCOL} on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}" with seed "${FOUNDRY_FUZZ_SEED}"
	@forge test --gas-report | tee trace.ansi

contract-% c-%:
	@echo Running tests for contract $* of Morpho-${PROTOCOL} on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}"
	@forge test -vvv --match-contract $* | tee trace.ansi

single-% s-%:
	@echo Running single test $* of Morpho-${PROTOCOL} on "${NETWORK}" at block "${FOUNDRY_FORK_BLOCK_NUMBER}"
	@forge test -vvvv --match-test $* | tee trace.ansi

storage-layout-generate:
	@./scripts/storage-layout.sh generate snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

storage-layout-check:
	@./scripts/storage-layout.sh check snapshots/.storage-layout-${PROTOCOL} Morpho RewardsManager Lens

storage-layout-generate-no-rewards:
	@./scripts/storage-layout.sh generate snapshots/.storage-layout-${PROTOCOL} Morpho Lens

storage-layout-check-no-rewards:
	@./scripts/storage-layout.sh check snapshots/.storage-layout-${PROTOCOL} Morpho Lens

config:
	@forge config


.PHONY: test config test-common foundry coverage
