# KAM Protocol Deployment Makefile
# Usage: make deploy-mainnet, make deploy-sepolia, make deploy-localhost
-include .env
export

.PHONY: help deploy-mainnet deploy-mainnet-dry-run deploy-sepolia deploy-sepolia-dry-run deploy-localhost deploy-localhost-dry-run config-mainnet config-mainnet-dry-run config-sepolia config-sepolia-dry-run config-localhost config-localhost-dry-run deploy-all config-all deploy-mock-assets verify-mainnet verify-sepolia verify clean clean-all configure-adapters register-modules format-output test test-parallel coverage

# Default target
help:
	@echo "KAM Protocol Deployment Commands"
	@echo "================================="
	@echo ""
	@echo "Deploy contracts (00-08):"
	@echo "make deploy-mainnet          - Deploy to mainnet"
	@echo "make deploy-mainnet-dry-run  - Simulate deployment to mainnet (no broadcast)"
	@echo "make deploy-sepolia          - Deploy to Sepolia testnet"
	@echo "make deploy-sepolia-dry-run  - Simulate deployment to Sepolia (no broadcast)"
	@echo "make deploy-localhost        - Deploy to localhost"
	@echo "make deploy-localhost-dry-run- Simulate deployment to localhost (no broadcast)"
	@echo ""
	@echo "Configure protocol (09-10):"
	@echo "make config-mainnet          - Configure on mainnet"
	@echo "make config-mainnet-dry-run  - Simulate configuration on mainnet (no broadcast)"
	@echo "make config-sepolia          - Configure on Sepolia testnet"
	@echo "make config-sepolia-dry-run  - Simulate configuration on Sepolia (no broadcast)"
	@echo "make config-localhost        - Configure on localhost"
	@echo "make config-localhost-dry-run- Simulate configuration on localhost (no broadcast)"
	@echo ""
	@echo "Verify contracts on Etherscan:"
	@echo "make verify-mainnet          - Verify contracts on mainnet Etherscan"
	@echo "make verify-sepolia          - Verify contracts on Sepolia Etherscan"
	@echo ""
	@echo "Other commands:"
	@echo "make verify             - Check deployment files exist"
	@echo "make clean              - Clean localhost deployment files"
	@echo "make clean-all          - Clean ALL deployment files (DANGER)"
	@echo ""
	@echo "Individual deployment steps (script/deployment/):"
	@echo "make deploy-mock-assets - Deploy mock assets for testnets (00)"
	@echo "make deploy-core        - Deploy core contracts (01-03)"
	@echo "make setup-singletons   - Register singletons (04)"
	@echo "make deploy-tokens      - Deploy kTokens (05)"
	@echo "make deploy-modules     - Deploy vault modules (06)"
	@echo "make deploy-vaults      - Deploy vaults (07)"
	@echo "make deploy-adapters    - Deploy adapters (08)"
	@echo "make deploy-insurance   - Deploy insurance smart account (12)"
	@echo ""
	@echo "Individual configuration steps (script/actions/):"
	@echo "make configure          - Configure protocol (09)"
	@echo "make configure-adapters - Configure adapter permissions (10)"
	@echo "make register-modules   - Register vault modules (11) [OPTIONAL]"

# Network-specific deployments
deploy-mainnet:
	@echo "🔴 Deploying to MAINNET..."
	@$(MAKE) deploy-all FORGE_ARGS="--rpc-url ${RPC_MAINNET} --broadcast --account keyDeployer --sender ${DEPLOYER_ADDRESS} --slow"

deploy-mainnet-dry-run:
	@echo "🔴 [DRY-RUN] Simulating deployment to MAINNET..."
	@$(MAKE) deploy-all FORGE_ARGS="--rpc-url ${RPC_MAINNET} --account keyDeployer --sender ${DEPLOYER_ADDRESS} --slow"

deploy-sepolia:
	@echo "🟡 Deploying to SEPOLIA..."
	@$(MAKE) deploy-mock-assets FORGE_ARGS="--rpc-url ${RPC_SEPOLIA} --broadcast --account keyDeployer --sender ${DEPLOYER_ADDRESS}	--slow"
	@$(MAKE) deploy-all FORGE_ARGS="--rpc-url ${RPC_SEPOLIA} --broadcast --account keyDeployer --sender ${DEPLOYER_ADDRESS}	--slow"

deploy-sepolia-dry-run:
	@echo "🟡 [DRY-RUN] Simulating deployment to SEPOLIA..."
	@$(MAKE) deploy-mock-assets FORGE_ARGS="--rpc-url ${RPC_SEPOLIA} --account keyDeployer --sender ${DEPLOYER_ADDRESS} --slow"
	@$(MAKE) deploy-all FORGE_ARGS="--rpc-url ${RPC_SEPOLIA} --account keyDeployer --sender ${DEPLOYER_ADDRESS} --slow"

deploy-localhost:
	@echo "🟢 Deploying to LOCALHOST..."
	@$(MAKE) deploy-mock-assets FORGE_ARGS="--rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --slow"
	@$(MAKE) deploy-all FORGE_ARGS="--rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --slow"

deploy-localhost-dry-run:
	@echo "🟢 [DRY-RUN] Simulating deployment to LOCALHOST..."
	@$(MAKE) deploy-mock-assets FORGE_ARGS="--rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --slow"
	@$(MAKE) deploy-all FORGE_ARGS="--rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --slow"

# Network-specific configurations
config-mainnet:
	@echo "🔴 Configuring on MAINNET..."
	@$(MAKE) config-all FORGE_ARGS="--rpc-url ${RPC_MAINNET} --broadcast --account keyDeployer --sender ${DEPLOYER_ADDRESS} --slow"

config-mainnet-dry-run:
	@echo "🔴 [DRY-RUN] Simulating configuration on MAINNET..."
	@$(MAKE) config-all FORGE_ARGS="--rpc-url ${RPC_MAINNET} --account keyDeployer --sender ${DEPLOYER_ADDRESS} --slow"

config-sepolia:
	@echo "🟡 Configuring on SEPOLIA..."
	@$(MAKE) config-all FORGE_ARGS="--rpc-url ${RPC_SEPOLIA} --broadcast --account keyDeployer --sender ${DEPLOYER_ADDRESS}	--slow"

config-sepolia-dry-run:
	@echo "🟡 [DRY-RUN] Simulating configuration on SEPOLIA..."
	@$(MAKE) config-all FORGE_ARGS="--rpc-url ${RPC_SEPOLIA} --account keyDeployer --sender ${DEPLOYER_ADDRESS} --slow"

config-localhost:
	@echo "🟢 Configuring on LOCALHOST..."
	@$(MAKE) config-all FORGE_ARGS="--rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --slow"

config-localhost-dry-run:
	@echo "🟢 [DRY-RUN] Simulating configuration on LOCALHOST..."
	@$(MAKE) config-all FORGE_ARGS="--rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --slow"

# Etherscan verification (mainnet)
verify-mainnet:
	@echo "🔍 Verifying contracts on MAINNET Etherscan..."
	@if [ ! -f "deployments/output/mainnet/addresses.json" ]; then \
		echo "❌ No mainnet deployment found"; \
		exit 1; \
	fi
	@echo "Verifying kRegistry implementation..."
	@forge verify-contract $$(jq -r '.contracts.kRegistryImpl' deployments/output/mainnet/addresses.json) src/kRegistry/kRegistry.sol:kRegistry --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying kMinter implementation..."
	@forge verify-contract $$(jq -r '.contracts.kMinterImpl' deployments/output/mainnet/addresses.json) src/kMinter.sol:kMinter --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying kAssetRouter implementation..."
	@forge verify-contract $$(jq -r '.contracts.kAssetRouterImpl' deployments/output/mainnet/addresses.json) src/kAssetRouter.sol:kAssetRouter --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying kTokenFactory..."
	@forge verify-contract $$(jq -r '.contracts.kTokenFactory' deployments/output/mainnet/addresses.json) src/kTokenFactory.sol:kTokenFactory --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --constructor-args $$(cast abi-encode "constructor(address,address)" $$(jq -r '.contracts.kRegistry' deployments/output/mainnet/addresses.json) $$(jq -r '.contracts.ERC1967Factory' deployments/output/mainnet/addresses.json)) --watch || true
	@echo "Verifying kToken implementation (via kTokenFactory.implementation())..."
	@forge verify-contract $$(cast call $$(jq -r '.contracts.kTokenFactory' deployments/output/mainnet/addresses.json) "implementation()(address)" --rpc-url ${RPC_MAINNET}) src/kToken.sol:kToken --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying kStakingVault implementation..."
	@forge verify-contract $$(jq -r '.contracts.kStakingVaultImpl' deployments/output/mainnet/addresses.json) src/kStakingVault/kStakingVault.sol:kStakingVault --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying ReaderModule..."
	@forge verify-contract $$(jq -r '.contracts.readerModule' deployments/output/mainnet/addresses.json) src/kStakingVault/modules/ReaderModule.sol:ReaderModule --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying AdapterGuardianModule..."
	@forge verify-contract $$(jq -r '.contracts.adapterGuardianModule' deployments/output/mainnet/addresses.json) src/kRegistry/modules/AdapterGuardianModule.sol:AdapterGuardianModule --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying VaultAdapter implementation..."
	@forge verify-contract $$(jq -r '.contracts.vaultAdapterImpl' deployments/output/mainnet/addresses.json) src/adapters/VaultAdapter.sol:VaultAdapter --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --watch || true
	@echo "Verifying ERC20ParameterChecker..."
	@forge verify-contract $$(jq -r '.contracts.erc20ParameterChecker' deployments/output/mainnet/addresses.json) src/adapters/parameters/ERC20ParameterChecker.sol:ERC20ParameterChecker --chain-id 1 --etherscan-api-key ${ETHERSCAN_MAINNET_KEY} --constructor-args $$(cast abi-encode "constructor(address)" $$(jq -r '.contracts.kRegistry' deployments/output/mainnet/addresses.json)) --watch || true
	@echo ""
	@echo "Note: kUSD/kBTC are ERC1967 proxies - Etherscan will auto-detect them once kToken implementation is verified"
	@echo "✅ Mainnet verification complete!"

# Etherscan verification (sepolia)
verify-sepolia:
	@echo "🔍 Verifying contracts on SEPOLIA Etherscan..."
	@if [ ! -f "deployments/output/sepolia/addresses.json" ]; then \
		echo "❌ No sepolia deployment found"; \
		exit 1; \
	fi
	@echo "Verifying kRegistry implementation..."
	@forge verify-contract $$(jq -r '.contracts.kRegistryImpl' deployments/output/sepolia/addresses.json) src/kRegistry/kRegistry.sol:kRegistry --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying kMinter implementation..."
	@forge verify-contract $$(jq -r '.contracts.kMinterImpl' deployments/output/sepolia/addresses.json) src/kMinter.sol:kMinter --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying kAssetRouter implementation..."
	@forge verify-contract $$(jq -r '.contracts.kAssetRouterImpl' deployments/output/sepolia/addresses.json) src/kAssetRouter.sol:kAssetRouter --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying kTokenFactory..."
	@forge verify-contract $$(jq -r '.contracts.kTokenFactory' deployments/output/sepolia/addresses.json) src/kTokenFactory.sol:kTokenFactory --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --constructor-args $$(cast abi-encode "constructor(address,address)" $$(jq -r '.contracts.kRegistry' deployments/output/sepolia/addresses.json) $$(jq -r '.contracts.ERC1967Factory' deployments/output/sepolia/addresses.json)) --watch || true
	@echo "Verifying kToken implementation (via kTokenFactory.implementation())..."
	@forge verify-contract $$(cast call $$(jq -r '.contracts.kTokenFactory' deployments/output/sepolia/addresses.json) "implementation()(address)" --rpc-url ${RPC_SEPOLIA}) src/kToken.sol:kToken --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying kStakingVault implementation..."
	@forge verify-contract $$(jq -r '.contracts.kStakingVaultImpl' deployments/output/sepolia/addresses.json) src/kStakingVault/kStakingVault.sol:kStakingVault --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying ReaderModule..."
	@forge verify-contract $$(jq -r '.contracts.readerModule' deployments/output/sepolia/addresses.json) src/kStakingVault/modules/ReaderModule.sol:ReaderModule --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying AdapterGuardianModule..."
	@forge verify-contract $$(jq -r '.contracts.adapterGuardianModule' deployments/output/sepolia/addresses.json) src/kRegistry/modules/AdapterGuardianModule.sol:AdapterGuardianModule --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying VaultAdapter implementation..."
	@forge verify-contract $$(jq -r '.contracts.vaultAdapterImpl' deployments/output/sepolia/addresses.json) src/adapters/VaultAdapter.sol:VaultAdapter --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --watch || true
	@echo "Verifying ERC20ParameterChecker..."
	@forge verify-contract $$(jq -r '.contracts.erc20ParameterChecker' deployments/output/sepolia/addresses.json) src/adapters/parameters/ERC20ParameterChecker.sol:ERC20ParameterChecker --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_SEPOLIA_KEY} --constructor-args $$(cast abi-encode "constructor(address)" $$(jq -r '.contracts.kRegistry' deployments/output/sepolia/addresses.json)) --watch || true
	@echo ""
	@echo "Note: kUSD/kBTC are ERC1967 proxies - Etherscan will auto-detect them once kToken implementation is verified"
	@echo "✅ Sepolia verification complete!"

# Complete deployment sequence (deploys contracts only)
deploy-all: deploy-core setup-singletons deploy-tokens deploy-modules deploy-vaults deploy-adapters deploy-insurance format-output
	@echo "✅ Protocol deployment finished!"

# Complete configuration sequence (configures deployed contracts)
config-all: configure configure-adapters format-output
	@echo "✅ Protocol configuration finished!"

# Format JSON output files
format-output:
	@echo "📝 Formatting JSON output files..."
	@for file in deployments/output/*/*.json; do \
		if [ -f "$$file" ]; then \
			echo "Formatting $$file"; \
			jq . "$$file" > "$$file.tmp" && mv "$$file.tmp" "$$file"; \
		fi; \
	done
	@echo "✅ JSON files formatted!"

# Mock assets (00) - Only for testnets
deploy-mock-assets:
	@echo "🪙 Deploying mock assets for testnet..."
	forge script script/deployment/00_DeployMockAssets.s.sol --sig "run()" $(FORGE_ARGS)

# Core contracts (01-03)
deploy-core:
	@echo "📦 Deploying core contracts..."
	forge script script/deployment/01_DeployRegistry.s.sol --sig "run()" $(FORGE_ARGS)
	forge script script/deployment/02_DeployMinter.s.sol --sig "run()" $(FORGE_ARGS)
	forge script script/deployment/03_DeployAssetRouter.s.sol --sig "run()" $(FORGE_ARGS)

# Registry setup (04)
setup-singletons:
	@echo "⚙️  Registry singleton setup..."
	forge script script/deployment/04_RegisterSingletons.s.sol --sig "run()" $(FORGE_ARGS)
	@echo "⚠️  Execute the displayed admin calls via admin account"

# Token deployment (05)
deploy-tokens:
	@echo "🪙 Token deployment setup..."
	forge script script/deployment/05_DeployTokens.s.sol --sig "run()" $(FORGE_ARGS)
	@echo "⚠️  Execute the displayed admin calls via admin account"

# Vault modules (06)
deploy-modules:
	@echo "🧩 Deploying vault modules..."
	forge script script/deployment/06_DeployVaultModules.s.sol --sig "run()" $(FORGE_ARGS)

# Vaults (07)
deploy-vaults:
	@echo "🏛️  Deploying vaults..."
	forge script script/deployment/07_DeployVaults.s.sol --sig "run()" $(FORGE_ARGS)

# Adapters (08)
deploy-adapters:
	@echo "🔌 Deploying adapters..."
	forge script script/deployment/08_DeployAdapters.s.sol --sig "run()" $(FORGE_ARGS)

# Insurance (12)
deploy-insurance:
	@echo "🛡️  Deploying insurance smart account..."
	forge script script/deployment/12_DeployInsuranceAccount.s.sol --sig "run()" $(FORGE_ARGS)

# Final configuration (09) - in actions folder
configure:
	@echo "⚙️  Executing protocol configuration..."
	forge script script/actions/09_ConfigureProtocol.s.sol --sig "run()" $(FORGE_ARGS)

# Adapter permissions configuration (10) - in actions folder
configure-adapters:
	@echo "🔐 Configuring adapter permissions..."
	forge script script/actions/10_ConfigureAdapterPermissions.s.sol --sig "run()" $(FORGE_ARGS)

# Register vault modules (11) - Optional step for adding ReaderModule to vaults - in actions folder
register-modules:
	@echo "📦 Registering vault modules..."
	forge script script/actions/11_RegisterVaultModules.s.sol --sig "run()" $(FORGE_ARGS)
	@echo "⚠️  Execute the displayed admin calls via admin account"

# Verification
verify:
	@echo "🔍 Verifying deployment..."
	@if [ ! -f "deployments/output/localhost/addresses.json" ] && [ ! -f "deployments/output/mainnet/addresses.json" ] && [ ! -f "deployments/output/sepolia/addresses.json" ]; then \
		echo "❌ No deployment files found"; \
		exit 1; \
	fi
	@echo "✅ Deployment files exist"
	@echo "📄 Check deployments/output/ for contract addresses"

# Development helpers

test:
	@echo "⚡ Running tests in parallel..."
	forge test

coverage:
	forge coverage

compile:
	@$(MAKE) check-selectors
	@$(MAKE) check-interface-completeness
	@$(MAKE) check-natspec
	forge fmt --check
	forge build --sizes --skip test

build:
	@$(MAKE) build-selectors
	@$(MAKE) build-interfaces
	forge fmt
	forge build --use $$(which solx)

clean:
	forge clean
	rm -rf deployments/output/localhost/addresses.json

clean-all:
	forge clean
	rm -rf deployments/output/*/addresses.json

# Documentation
docs:
	forge doc --serve --port 4000

check-natspec:
	@echo "🔍 Checking NatSpec documentation completeness..."
	@bash -c '\
	found_issues=0; \
	\
	get_interface_file() { \
		local contract_file=$$1; \
		local interface_name=$$(grep -oE "is[[:space:]]+I[A-Za-z0-9_]+" "$$contract_file" | head -n 1 | sed -E "s/is[[:space:]]+//"); \
		if [ -z "$$interface_name" ]; then \
			echo ""; \
			return; \
		fi; \
		local interface_file=$$(find src/interfaces -type f -name "$$interface_name.sol" | head -n 1); \
		echo "$$interface_file"; \
	}; \
	\
	get_specific_interface_file() { \
		local interface_name=$$1; \
		local interface_file=$$(find src/interfaces -type f -name "$$interface_name.sol" | head -n 1); \
		echo "$$interface_file"; \
	}; \
	\
	get_function_natspec() { \
		local file=$$1; \
		local func_name=$$2; \
		local in_natspec=0; \
		local in_function=0; \
		local natspec_params=(); \
		local has_return=0; \
		local inheritdoc_interface=""; \
		\
		while IFS= read -r line; do \
			if echo "$$line" | grep -q "/// @inheritdoc"; then \
				inheritdoc_interface=$$(echo "$$line" | sed -n "s/.*@inheritdoc[[:space:]]\+\([A-Za-z0-9_]\+\).*/\1/p"); \
				echo "INHERITDOC:$$inheritdoc_interface"; \
				return; \
			fi; \
			\
			if echo "$$line" | grep -q "/// @param"; then \
				param_name=$$(echo "$$line" | sed -n "s/.*@param[[:space:]]\+\([a-zA-Z0-9_]\+\).*/\1/p"); \
				if [ -n "$$param_name" ]; then \
					natspec_params+=("$$param_name"); \
				fi; \
			fi; \
			\
			if echo "$$line" | grep -q "/// @return"; then \
				has_return=1; \
			fi; \
			\
			if echo "$$line" | grep -qE "function[[:space:]]+$$func_name[[:space:]]*\("; then \
				break; \
			fi; \
		done < "$$file"; \
		\
		echo "$${natspec_params[@]}|$$has_return"; \
	}; \
	\
	for file in $$(find src -name "*.sol" -type f ! -path "src/vendor/*" ! -path "src/interfaces/*" ! -path "src/adapters/parameters/*"); do \
		echo "Checking $$file..."; \
		interface_file=$$(get_interface_file "$$file"); \
		\
		temp_file=$$(mktemp); \
		in_function=0; \
		func_name=""; \
		func_line=""; \
		func_start_line=0; \
		current_line=0; \
		has_inheritdoc=0; \
		inheritdoc_interface=""; \
		\
		while IFS= read -r line; do \
			current_line=$$((current_line + 1)); \
			clean_line=$$(echo "$$line" | sed "s://.*$$::"); \
			\
			if echo "$$line" | grep -q "/// @inheritdoc"; then \
				has_inheritdoc=1; \
				inheritdoc_interface=$$(echo "$$line" | sed -n "s/.*@inheritdoc[[:space:]]\+\([A-Za-z0-9_]\+\).*/\1/p"); \
			fi; \
			\
			if echo "$$clean_line" | grep -qE "function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\("; then \
				func_name=$$(echo "$$clean_line" | sed -n "s/.*function[[:space:]]\+\([a-zA-Z0-9_]\+\)[[:space:]]*(.*/\1/p"); \
				func_line="$$clean_line"; \
				func_start_line=$$current_line; \
				in_function=1; \
			fi; \
			\
			if [ $$in_function -eq 1 ]; then \
				func_line="$$func_line $$clean_line"; \
				\
				if echo "$$clean_line" | grep -qE "\{|;"; then \
					is_public_external=0; \
					if echo "$$func_line" | grep -qE "(public|external)"; then \
						is_public_external=1; \
					fi; \
					\
					if [ $$is_public_external -eq 1 ] && [ -n "$$func_name" ] && [ "$$func_name" != "constructor" ]; then \
						if [ $$has_inheritdoc -eq 1 ]; then \
							target_interface_file=""; \
							if [ -n "$$inheritdoc_interface" ]; then \
								target_interface_file=$$(get_specific_interface_file "$$inheritdoc_interface"); \
							else \
								target_interface_file="$$interface_file"; \
							fi; \
							\
							if [ -z "$$target_interface_file" ] || [ ! -f "$$target_interface_file" ]; then \
								if [ -n "$$inheritdoc_interface" ]; then \
									echo "  ⚠️  Function $$func_name has @inheritdoc $$inheritdoc_interface but interface file not found (line $$func_start_line)"; \
								else \
									echo "  ⚠️  Function $$func_name has @inheritdoc but no interface file found (line $$func_start_line)"; \
								fi; \
								found_issues=$$((found_issues + 1)); \
							fi; \
							has_inheritdoc=0; \
							inheritdoc_interface=""; \
						else \
							actual_params=$$(echo "$$func_line" | sed -n "s/.*function[[:space:]]\+[a-zA-Z0-9_]\+[[:space:]]*(\([^)]*\)).*/\1/p" | grep -o "[a-zA-Z0-9_]\+[[:space:]]\+[a-zA-Z0-9_]\+" | grep -v "memory" | awk "{print \$$NF}" | grep -v "^$$"); \
							\
							has_return=0; \
							if echo "$$func_line" | grep -qE "returns[[:space:]]*\("; then \
								has_return=1; \
							fi; \
							\
							natspec_info=$$(get_function_natspec "$$file" "$$func_name"); \
							\
							if echo "$$natspec_info" | grep -q "^INHERITDOC:"; then \
								inheritdoc_from_natspec=$$(echo "$$natspec_info" | cut -d: -f2); \
								target_interface_file=""; \
								if [ -n "$$inheritdoc_from_natspec" ]; then \
									target_interface_file=$$(get_specific_interface_file "$$inheritdoc_from_natspec"); \
								else \
									target_interface_file="$$interface_file"; \
								fi; \
								\
								if [ -z "$$target_interface_file" ] || [ ! -f "$$target_interface_file" ]; then \
									if [ -n "$$inheritdoc_from_natspec" ]; then \
										echo "  ⚠️  Function $$func_name has @inheritdoc $$inheritdoc_from_natspec but interface file not found (line $$func_start_line)"; \
									else \
										echo "  ⚠️  Function $$func_name has @inheritdoc but no interface file found (line $$func_start_line)"; \
									fi; \
									found_issues=$$((found_issues + 1)); \
								fi; \
							else \
								natspec_params=$$(echo "$$natspec_info" | cut -d"|" -f1); \
								natspec_has_return=$$(echo "$$natspec_info" | cut -d"|" -f2); \
								\
								for param in $$actual_params; do \
									found=0; \
									for natspec_param in $$natspec_params; do \
										if [ "$$param" = "$$natspec_param" ]; then \
											found=1; \
											break; \
										fi; \
									done; \
									if [ $$found -eq 0 ]; then \
										echo "  ❌ Missing @param $$param in function $$func_name (line $$func_start_line)"; \
										found_issues=$$((found_issues + 1)); \
									fi; \
								done; \
								\
								if [ $$has_return -eq 1 ] && [ "$$natspec_has_return" != "1" ]; then \
									echo "  ❌ Missing @return in function $$func_name (line $$func_start_line)"; \
									found_issues=$$((found_issues + 1)); \
								fi; \
							fi; \
						fi; \
					fi; \
					\
					in_function=0; \
					func_name=""; \
					func_line=""; \
					has_inheritdoc=0; \
					inheritdoc_interface=""; \
				fi; \
			fi; \
		done < "$$file"; \
	done; \
	if [ $$found_issues -gt 0 ]; then \
		echo ""; \
		echo "❌ Found $$found_issues NatSpec issue(s)"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All public/external functions have complete NatSpec documentation"; \
	fi'

# Verify that IModule contracts have complete selectors() functions
check-selectors:
	@echo "🔍 Checking IModule contracts for complete selectors()..."
	@bash -c '\
	found_issues=0; \
	for file in $$(find src -name "*.sol" -type f); do \
		if grep -q "IModule" "$$file" && grep -q "function selectors()" "$$file"; then \
			echo "Checking $$file..."; \
			contract_name=$$(basename "$$file" .sol); \
			selectors=$$(grep -E "function [a-zA-Z0-9_]+\(" "$$file" | \
				grep -E "(external|public)" | \
				grep -v "function selectors()" | \
				grep -v "constructor" | \
				grep -v "^[[:space:]]*///" | \
				grep -v "^[[:space:]]*\*" | \
				sed "s/.*function \([a-zA-Z0-9_]*\).*/\1/"); \
			selectors_array=$$(grep -A 100 "function selectors()" "$$file" | \
				grep "this\." | \
				sed "s/.*this\.\([a-zA-Z0-9_]*\).*/\1/"); \
			for selector in $$selectors; do \
				if ! echo "$$selectors_array" | grep -q "$$selector"; then \
					echo "  ❌ Missing selector: $$selector in $$contract_name"; \
					found_issues=$$((found_issues + 1)); \
				fi; \
			done; \
			if [ $$found_issues -eq 0 ]; then \
				echo "  ✅ All selectors present in $$contract_name"; \
			fi; \
		fi; \
	done; \
	if [ $$found_issues -gt 0 ]; then \
		echo ""; \
		echo "❌ Found $$found_issues missing selector(s)"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All IModule contracts have complete selectors() functions"; \
	fi'

# Automatically fix IModule contracts by rebuilding selectors() function
build-selectors:
	@echo "🔧 Fixing IModule contracts selectors()..."
	@bash -c '\
	fixed_count=0; \
	for file in $$(find src -name "*.sol" -type f); do \
		filename=$$(basename "$$file"); \
		if [ "$$filename" = "IModule.sol" ]; then \
			echo "⏭️  Skipping $$file (interface file)"; \
			continue; \
		fi; \
		\
		if grep -q "IModule" "$$file" && grep -q "function selectors()" "$$file"; then \
			echo "Checking $$file..."; \
			contract_name=$$(basename "$$file" .sol); \
			\
			selectors=(); \
			in_function=0; \
			is_public_external=0; \
			func_name=""; \
			\
			while IFS= read -r line; do \
				clean_line=$$(echo "$$line" | sed "s://.*$$::"); \
				\
				if echo "$$clean_line" | grep -q "function selectors()"; then \
					in_function=0; \
					continue; \
				fi; \
				\
				if echo "$$clean_line" | grep -q "constructor"; then \
					in_function=0; \
					continue; \
				fi; \
				\
				if echo "$$clean_line" | grep -qE "function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\("; then \
					func_name=$$(echo "$$clean_line" | sed -n "s/.*function[[:space:]]*\([a-zA-Z0-9_]*\)[[:space:]]*(.*/\1/p"); \
					in_function=1; \
					is_public_external=0; \
					\
					if echo "$$clean_line" | grep -qE "(public|external)"; then \
						is_public_external=1; \
					fi; \
				fi; \
				\
				if [ $$in_function -eq 1 ] && [ $$is_public_external -eq 0 ]; then \
					if echo "$$clean_line" | grep -qE "(public|external)"; then \
						is_public_external=1; \
					fi; \
				fi; \
				\
				if [ $$in_function -eq 1 ] && echo "$$clean_line" | grep -qE "\{|;"; then \
					if [ $$is_public_external -eq 1 ] && [ -n "$$func_name" ]; then \
						selectors+=("$$func_name"); \
					fi; \
					in_function=0; \
					func_name=""; \
				fi; \
			done < "$$file"; \
			\
			num_selectors=$${#selectors[@]}; \
			echo "  📋 Found $$num_selectors function(s): $${selectors[*]}"; \
			\
			temp_file=$$(mktemp); \
			in_selectors_func=0; \
			skip_until_closing=0; \
			indent=""; \
			\
			while IFS= read -r line; do \
				if echo "$$line" | grep -q "function selectors()"; then \
					in_selectors_func=1; \
					skip_until_closing=1; \
					indent=$$(echo "$$line" | sed "s/\(^[[:space:]]*\).*/\1/"); \
					echo "$$line" >> "$$temp_file"; \
					echo "$${indent}    bytes4[] memory moduleSelectors = new bytes4[]($$num_selectors);" >> "$$temp_file"; \
					\
					idx=0; \
					for selector in "$${selectors[@]}"; do \
						echo "$${indent}    moduleSelectors[$$idx] = this.$$selector.selector;" >> "$$temp_file"; \
						idx=$$((idx + 1)); \
					done; \
					\
					echo "$${indent}    return moduleSelectors;" >> "$$temp_file"; \
					continue; \
				fi; \
				\
				if [ $$skip_until_closing -eq 1 ]; then \
					if echo "$$line" | grep -qE "^$${indent}}"; then \
						skip_until_closing=0; \
						in_selectors_func=0; \
						echo "$$line" >> "$$temp_file"; \
					fi; \
					continue; \
				fi; \
				\
				echo "$$line" >> "$$temp_file"; \
			done < "$$file"; \
			\
			mv "$$temp_file" "$$file"; \
			echo "  ✅ Rebuilt selectors() for $$contract_name with $$num_selectors selector(s)"; \
			fixed_count=$$((fixed_count + 1)); \
		fi; \
	done; \
	if [ $$fixed_count -gt 0 ]; then \
		echo ""; \
		echo "✅ Rebuilt selectors() in $$fixed_count contract(s)"; \
		echo "⚠️  Please review the changes and run tests"; \
	else \
		echo ""; \
		echo "ℹ️  No IModule contracts found to fix"; \
	fi'
	
check-interface-completeness:
	@echo " Checking contracts for interface completeness..."
	@bash -c '\
	found_issues=0; \
	get_interface_funcs() { \
		local interface_file=$$1; \
		local funcs=""; \
		local inherited_interfaces=$$(grep -E "interface[[:space:]]+[A-Za-z0-9_]+[[:space:]]+is[[:space:]]+" "$$interface_file" | sed -E "s/.*is[[:space:]]+(.+)[[:space:]]*\{.*/\1/" | tr "," "\n" | sed "s/^[[:space:]]*//;s/[[:space:]]*$$//"); \
		funcs=$$(grep -E "function[[:space:]]+[A-Za-z0-9_]+\(" "$$interface_file" | sed -E "s/.*function[[:space:]]+([A-Za-z0-9_]+)\(.*/\1/"); \
		for inherited in $$inherited_interfaces; do \
			inherited_file=$$(find src/interfaces -type f -name "$$inherited.sol" | head -n 1); \
			if [ -f "$$inherited_file" ]; then \
				inherited_funcs=$$(get_interface_funcs "$$inherited_file"); \
				funcs=$$(printf "%s\n%s" "$$funcs" "$$inherited_funcs"); \
			fi; \
		done; \
		echo "$$funcs" | grep -v "^$$" | sort -u; \
	}; \
	for file in $$(find src -name "*.sol" -type f ! -path "src/vendor/*" ! -path "src/interfaces/*" ! -path "src/adapters/parameters/*"); do \
		if grep -qE "contract[[:space:]]+[A-Za-z0-9_]+[[:space:]]+is[[:space:]]+I" "$$file"; then \
			contract_name=$$(basename "$$file" .sol); \
			interface_name=$$(grep -oE "is[[:space:]]+I[A-Za-z0-9_]+" "$$file" | head -n 1 | sed -E "s/is[[:space:]]+//"); \
			if [ -z "$$interface_name" ]; then \
				continue; \
			fi; \
			echo "Checking $$contract_name against $$interface_name..."; \
			interface_file=$$(find src/interfaces -type f -name "$$interface_name.sol" | head -n 1); \
			if [ ! -f "$$interface_file" ]; then \
				echo "  ⚠️  Interface file not found: $$interface_name.sol"; \
				found_issues=$$((found_issues + 1)); \
				continue; \
			fi; \
			contract_funcs=$$(grep -E "function[[:space:]]+[A-Za-z0-9_]+\(" "$$file" | grep -E "(public|external)" | sed -E "s/.*function[[:space:]]+([A-Za-z0-9_]+)\(.*/\1/" | grep -vE "^(initialize|selectors)$$"); \
			interface_funcs=$$(get_interface_funcs "$$interface_file"); \
			for func in $$contract_funcs; do \
				if ! echo "$$interface_funcs" | grep -q "^$$func$$"; then \
					echo "  ❌ Missing in $$interface_name: $$func"; \
					found_issues=$$((found_issues + 1)); \
				fi; \
			done; \
		fi; \
	done; \
	if [ $$found_issues -gt 0 ]; then \
		echo ""; \
		echo "  Found $$found_issues missing interface function(s)"; \
		exit 1; \
	else \
		echo ""; \
		echo "  ✅ All contracts match their interfaces"; \
	fi'

build-interfaces:
	@echo " Building and updating interfaces..."
	@bash -c '\
	get_interface_funcs() { \
		local interface_file=$$1; \
		local funcs=""; \
		local inherited_interfaces=$$(grep -E "interface[[:space:]]+[A-Za-z0-9_]+[[:space:]]+is[[:space:]]+" "$$interface_file" | sed -E "s/.*is[[:space:]]+(.+)[[:space:]]*\{.*/\1/" | tr "," "\n" | sed "s/^[[:space:]]*//;s/[[:space:]]*$$//"); \
		funcs=$$(grep -E "function[[:space:]]+[A-Za-z0-9_]+\(" "$$interface_file" | sed -E "s/.*function[[:space:]]+([A-Za-z0-9_]+)\(.*/\1/"); \
		for inherited in $$inherited_interfaces; do \
			inherited_file=$$(find src/interfaces -type f -name "$$inherited.sol" | head -n 1); \
			if [ -f "$$inherited_file" ]; then \
				inherited_funcs=$$(get_interface_funcs "$$inherited_file"); \
				funcs=$$(printf "%s\n%s" "$$funcs" "$$inherited_funcs"); \
			fi; \
		done; \
		echo "$$funcs" | grep -v "^$$" | sort -u; \
	}; \
	for file in $$(find src -name "*.sol" -type f ! -path "src/vendor/*" ! -path "src/interfaces/*" ! -path "src/adapters/parameters/*"); do \
		if grep -qE "contract[[:space:]]+[A-Za-z0-9_]+[[:space:]]+is[[:space:]]+I" "$$file"; then \
			contract_name=$$(basename "$$file" .sol); \
			interface_name=$$(grep -oE "is[[:space:]]+I[A-Za-z0-9_]+" "$$file" | head -n 1 | sed -E "s/is[[:space:]]+//"); \
			if [ -z "$$interface_name" ]; then \
				continue; \
			fi; \
			interface_file=$$(find src/interfaces -type f -name "$$interface_name.sol" | head -n 1); \
			if [ ! -f "$$interface_file" ]; then \
				echo "  ⚠️  Interface file not found: $$interface_name.sol - skipping"; \
				continue; \
			fi; \
			contract_funcs=$$(grep -E "function[[:space:]]+[A-Za-z0-9_]+\(" "$$file" | grep -E "(public|external)" | sed -E "s/.*function[[:space:]]+([A-Za-z0-9_]+)\(.*/\1/" | grep -vE "^(initialize|selectors)$$"); \
			interface_funcs=$$(get_interface_funcs "$$interface_file"); \
			missing_funcs=""; \
			for func in $$contract_funcs; do \
				if ! echo "$$interface_funcs" | grep -q "^$$func$$"; then \
					missing_funcs="$$missing_funcs $$func"; \
				fi; \
			done; \
			if [ -n "$$missing_funcs" ]; then \
				echo "Updating $$interface_name with missing functions from $$contract_name..."; \
				temp_file=$$(mktemp); \
				cp "$$interface_file" "$$temp_file"; \
				for func in $$missing_funcs; do \
					func_signature=$$(grep -E "function[[:space:]]+$$func\(" "$$file" | grep -E "(public|external)" | head -n 1 | sed -E "s/[[:space:]]*(public|external|internal|private)[[:space:]]*/ external /g; s/\{.*//; s/[[:space:]]+$$//" | sed "s/$$/;/"); \
					if [ -n "$$func_signature" ]; then \
						echo "  ➕ Adding: $$func"; \
						awk -v sig="    $$func_signature" "/^}[[:space:]]*$$/ {print sig; print; next} {print}" "$$temp_file" > "$$temp_file.new" && mv "$$temp_file.new" "$$temp_file"; \
					fi; \
				done; \
				mv "$$temp_file" "$$interface_file"; \
				echo "  ✅ Updated $$interface_name"; \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "  ✅ Interface building complete"'

# Color output
RED    = \033[0;31m
GREEN  = \033[0;32m  
YELLOW = \033[0;33m
BLUE   = \033[0;34m
NC     = \033[0m # No Color