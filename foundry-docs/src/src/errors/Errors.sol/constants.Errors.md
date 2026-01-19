# Constants
[Git Source](https://github.com/VerisLabs/KAM/blob/ee79211268af43ace88134525ab3a518754a1e4e/src/errors/Errors.sol)

### KASSETROUTER_ALREADY_REGISTERED
KAM Protocol Error Codes - Centralized error code constants for the KAM protocol.
All error codes use contract-specific prefixes for easier debugging:
- A*: kAssetRouter errors
- BA*: BaseAdapter errors
- BV*: BaseVault errors
- B*: kBatchReceiver errors
- C*: Custodial adapter errors
- F*: kTokenFactory errors
- K*: kBase errors
- M*: kMinter errors
- R*: kRegistry errors
- SV*: kStakingVault errors
- T*: kToken errors
- VB*: VaultBatches errors
- VC*: VaultClaims errors
- VF*: VaultFees errors


```solidity
string constant KASSETROUTER_ALREADY_REGISTERED = "A1"
```

### KASSETROUTER_BATCH_CLOSED

```solidity
string constant KASSETROUTER_BATCH_CLOSED = "A2"
```

### KASSETROUTER_BATCH_ID_PROPOSED

```solidity
string constant KASSETROUTER_BATCH_ID_PROPOSED = "A3"
```

### KASSETROUTER_BATCH_SETTLED

```solidity
string constant KASSETROUTER_BATCH_SETTLED = "A4"
```

### KASSETROUTER_COOLDOWN_IS_UP

```solidity
string constant KASSETROUTER_COOLDOWN_IS_UP = "A5"
```

### KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE

```solidity
string constant KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE = "A6"
```

### KASSETROUTER_INVALID_COOLDOWN

```solidity
string constant KASSETROUTER_INVALID_COOLDOWN = "A7"
```

### KASSETROUTER_INVALID_VAULT

```solidity
string constant KASSETROUTER_INVALID_VAULT = "A8"
```

### KASSETROUTER_IS_PAUSED

```solidity
string constant KASSETROUTER_IS_PAUSED = "A9"
```

### KASSETROUTER_NO_PROPOSAL

```solidity
string constant KASSETROUTER_NO_PROPOSAL = "A10"
```

### KASSETROUTER_ONLY_KMINTER

```solidity
string constant KASSETROUTER_ONLY_KMINTER = "A11"
```

### KASSETROUTER_ONLY_KSTAKING_VAULT

```solidity
string constant KASSETROUTER_ONLY_KSTAKING_VAULT = "A12"
```

### KASSETROUTER_PROPOSAL_EXECUTED

```solidity
string constant KASSETROUTER_PROPOSAL_EXECUTED = "A13"
```

### KASSETROUTER_PROPOSAL_EXISTS

```solidity
string constant KASSETROUTER_PROPOSAL_EXISTS = "A14"
```

### KASSETROUTER_PROPOSAL_NOT_FOUND

```solidity
string constant KASSETROUTER_PROPOSAL_NOT_FOUND = "A15"
```

### KASSETROUTER_WRONG_ROLE

```solidity
string constant KASSETROUTER_WRONG_ROLE = "A16"
```

### KASSETROUTER_ZERO_ADDRESS

```solidity
string constant KASSETROUTER_ZERO_ADDRESS = "A17"
```

### KASSETROUTER_ZERO_AMOUNT

```solidity
string constant KASSETROUTER_ZERO_AMOUNT = "A18"
```

### KASSETROUTER_INVALID_MAX_DELTA

```solidity
string constant KASSETROUTER_INVALID_MAX_DELTA = "A19"
```

### KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME

```solidity
string constant KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME = "A20"
```

### KASSETROUTER_NOT_BATCH_CLOSED

```solidity
string constant KASSETROUTER_NOT_BATCH_CLOSED = "A21"
```

### KASSETROUTER_PROPOSAL_NOT_ACCEPTED

```solidity
string constant KASSETROUTER_PROPOSAL_NOT_ACCEPTED = "A22"
```

### KASSETROUTER_NO_APPROVAL_REQUIRED

```solidity
string constant KASSETROUTER_NO_APPROVAL_REQUIRED = "A23"
```

### KASSETROUTER_PROPOSAL_ALREADY_ACCEPTED

```solidity
string constant KASSETROUTER_PROPOSAL_ALREADY_ACCEPTED = "A24"
```

### ADAPTER_ALREADY_INITIALIZED

```solidity
string constant ADAPTER_ALREADY_INITIALIZED = "BA1"
```

### ADAPTER_INVALID_REGISTRY

```solidity
string constant ADAPTER_INVALID_REGISTRY = "BA2"
```

### ADAPTER_TRANSFER_FAILED

```solidity
string constant ADAPTER_TRANSFER_FAILED = "BA3"
```

### ADAPTER_WRONG_ASSET

```solidity
string constant ADAPTER_WRONG_ASSET = "BA4"
```

### ADAPTER_WRONG_ROLE

```solidity
string constant ADAPTER_WRONG_ROLE = "BA5"
```

### ADAPTER_ZERO_ADDRESS

```solidity
string constant ADAPTER_ZERO_ADDRESS = "BA6"
```

### ADAPTER_ZERO_AMOUNT

```solidity
string constant ADAPTER_ZERO_AMOUNT = "BA7"
```

### ADAPTER_INSUFFICIENT_BALANCE

```solidity
string constant ADAPTER_INSUFFICIENT_BALANCE = "BA8"
```

### BASEVAULT_ALREADY_INITIALIZED

```solidity
string constant BASEVAULT_ALREADY_INITIALIZED = "BV1"
```

### BASEVAULT_CONTRACT_NOT_FOUND

```solidity
string constant BASEVAULT_CONTRACT_NOT_FOUND = "BV2"
```

### BASEVAULT_INVALID_REGISTRY

```solidity
string constant BASEVAULT_INVALID_REGISTRY = "BV3"
```

### BASEVAULT_INVALID_VAULT

```solidity
string constant BASEVAULT_INVALID_VAULT = "BV4"
```

### BASEVAULT_NOT_INITIALIZED

```solidity
string constant BASEVAULT_NOT_INITIALIZED = "BV5"
```

### KBATCHRECEIVER_ALREADY_INITIALIZED

```solidity
string constant KBATCHRECEIVER_ALREADY_INITIALIZED = "B1"
```

### KBATCHRECEIVER_ONLY_KMINTER

```solidity
string constant KBATCHRECEIVER_ONLY_KMINTER = "B3"
```

### KBATCHRECEIVER_TRANSFER_FAILED

```solidity
string constant KBATCHRECEIVER_TRANSFER_FAILED = "B4"
```

### KBATCHRECEIVER_WRONG_ASSET

```solidity
string constant KBATCHRECEIVER_WRONG_ASSET = "B5"
```

### KBATCHRECEIVER_ZERO_ADDRESS

```solidity
string constant KBATCHRECEIVER_ZERO_ADDRESS = "B6"
```

### KBATCHRECEIVER_ZERO_AMOUNT

```solidity
string constant KBATCHRECEIVER_ZERO_AMOUNT = "B7"
```

### KBATCHRECEIVER_INSUFFICIENT_BALANCE

```solidity
string constant KBATCHRECEIVER_INSUFFICIENT_BALANCE = "B8"
```

### CUSTODIAL_INVALID_CUSTODIAL_ADDRESS

```solidity
string constant CUSTODIAL_INVALID_CUSTODIAL_ADDRESS = "C1"
```

### CUSTODIAL_TRANSFER_FAILED

```solidity
string constant CUSTODIAL_TRANSFER_FAILED = "C2"
```

### CUSTODIAL_VAULT_DESTINATION_NOT_SET

```solidity
string constant CUSTODIAL_VAULT_DESTINATION_NOT_SET = "C3"
```

### CUSTODIAL_WRONG_ASSET

```solidity
string constant CUSTODIAL_WRONG_ASSET = "C4"
```

### CUSTODIAL_WRONG_ROLE

```solidity
string constant CUSTODIAL_WRONG_ROLE = "C5"
```

### CUSTODIAL_ZERO_ADDRESS

```solidity
string constant CUSTODIAL_ZERO_ADDRESS = "C6"
```

### CUSTODIAL_ZERO_AMOUNT

```solidity
string constant CUSTODIAL_ZERO_AMOUNT = "C7"
```

### KBASE_ALREADY_INITIALIZED

```solidity
string constant KBASE_ALREADY_INITIALIZED = "K1"
```

### KBASE_INVALID_REGISTRY

```solidity
string constant KBASE_INVALID_REGISTRY = "K2"
```

### KBASE_NOT_INITIALIZED

```solidity
string constant KBASE_NOT_INITIALIZED = "K3"
```

### KBASE_WRONG_ROLE

```solidity
string constant KBASE_WRONG_ROLE = "K4"
```

### KBASE_ZERO_ADDRESS

```solidity
string constant KBASE_ZERO_ADDRESS = "K5"
```

### KBASE_ZERO_AMOUNT

```solidity
string constant KBASE_ZERO_AMOUNT = "K6"
```

### KBASE_TRANSFER_FAILED

```solidity
string constant KBASE_TRANSFER_FAILED = "K7"
```

### KBASE_WRONG_ASSET

```solidity
string constant KBASE_WRONG_ASSET = "K8"
```

### KBASE_CONTRACT_NOT_FOUND

```solidity
string constant KBASE_CONTRACT_NOT_FOUND = "K9"
```

### KBASE_ASSET_NOT_SUPPORTED

```solidity
string constant KBASE_ASSET_NOT_SUPPORTED = "K10"
```

### KBASE_INVALID_VAULT

```solidity
string constant KBASE_INVALID_VAULT = "K11"
```

### KMINTER_BATCH_CLOSED

```solidity
string constant KMINTER_BATCH_CLOSED = "M1"
```

### KMINTER_BATCH_SETTLED

```solidity
string constant KMINTER_BATCH_SETTLED = "M2"
```

### KMINTER_INSUFFICIENT_BALANCE

```solidity
string constant KMINTER_INSUFFICIENT_BALANCE = "M3"
```

### KMINTER_IS_PAUSED

```solidity
string constant KMINTER_IS_PAUSED = "M4"
```

### KMINTER_REQUEST_NOT_FOUND

```solidity
string constant KMINTER_REQUEST_NOT_FOUND = "M5"
```

### KMINTER_WRONG_ASSET

```solidity
string constant KMINTER_WRONG_ASSET = "M6"
```

### KMINTER_WRONG_ROLE

```solidity
string constant KMINTER_WRONG_ROLE = "M7"
```

### KMINTER_ZERO_ADDRESS

```solidity
string constant KMINTER_ZERO_ADDRESS = "M8"
```

### KMINTER_ZERO_AMOUNT

```solidity
string constant KMINTER_ZERO_AMOUNT = "M9"
```

### KMINTER_BATCH_MINT_REACHED

```solidity
string constant KMINTER_BATCH_MINT_REACHED = "M10"
```

### KMINTER_BATCH_REDEEM_REACHED

```solidity
string constant KMINTER_BATCH_REDEEM_REACHED = "M11"
```

### KMINTER_BATCH_NOT_CLOSED

```solidity
string constant KMINTER_BATCH_NOT_CLOSED = "M12"
```

### KMINTER_BATCH_NOT_VALID

```solidity
string constant KMINTER_BATCH_NOT_VALID = "M13"
```

### KMINTER_BATCH_NOT_SETTLED

```solidity
string constant KMINTER_BATCH_NOT_SETTLED = "M14"
```

### KMINTER_UNAUTHORIZED

```solidity
string constant KMINTER_UNAUTHORIZED = "M15"
```

### KREGISTRY_ADAPTER_ALREADY_SET

```solidity
string constant KREGISTRY_ADAPTER_ALREADY_SET = "R1"
```

### KREGISTRY_ALREADY_REGISTERED

```solidity
string constant KREGISTRY_ALREADY_REGISTERED = "R2"
```

### KREGISTRY_ASSET_NOT_SUPPORTED

```solidity
string constant KREGISTRY_ASSET_NOT_SUPPORTED = "R3"
```

### KREGISTRY_INVALID_ADAPTER

```solidity
string constant KREGISTRY_INVALID_ADAPTER = "R4"
```

### KREGISTRY_TRANSFER_FAILED

```solidity
string constant KREGISTRY_TRANSFER_FAILED = "R5"
```

### KREGISTRY_WRONG_ASSET

```solidity
string constant KREGISTRY_WRONG_ASSET = "R6"
```

### KREGISTRY_WRONG_ROLE

```solidity
string constant KREGISTRY_WRONG_ROLE = "R7"
```

### KREGISTRY_ZERO_ADDRESS

```solidity
string constant KREGISTRY_ZERO_ADDRESS = "R8"
```

### KREGISTRY_ZERO_AMOUNT

```solidity
string constant KREGISTRY_ZERO_AMOUNT = "R9"
```

### KREGISTRY_FEE_EXCEEDS_MAXIMUM

```solidity
string constant KREGISTRY_FEE_EXCEEDS_MAXIMUM = "R10"
```

### KREGISTRY_SELECTOR_ALREADY_SET

```solidity
string constant KREGISTRY_SELECTOR_ALREADY_SET = "R11"
```

### KREGISTRY_SELECTOR_NOT_FOUND

```solidity
string constant KREGISTRY_SELECTOR_NOT_FOUND = "R12"
```

### KREGISTRY_KTOKEN_ALREADY_SET

```solidity
string constant KREGISTRY_KTOKEN_ALREADY_SET = "R13"
```

### KREGISTRY_EMPTY_STRING

```solidity
string constant KREGISTRY_EMPTY_STRING = "R14"
```

### KREGISTRY_ASSET_IN_USE

```solidity
string constant KREGISTRY_ASSET_IN_USE = "R15"
```

### KREGISTRY_VAULT_TYPE_ASSIGNED

```solidity
string constant KREGISTRY_VAULT_TYPE_ASSIGNED = "R16"
```

### GUARDIANMODULE_UNAUTHORIZED

```solidity
string constant GUARDIANMODULE_UNAUTHORIZED = "GM1"
```

### GUARDIANMODULE_NOT_ALLOWED

```solidity
string constant GUARDIANMODULE_NOT_ALLOWED = "GM2"
```

### GUARDIANMODULE_INVALID_EXECUTOR

```solidity
string constant GUARDIANMODULE_INVALID_EXECUTOR = "GM3"
```

### GUARDIANMODULE_SELECTOR_ALREADY_SET

```solidity
string constant GUARDIANMODULE_SELECTOR_ALREADY_SET = "GM4"
```

### GUARDIANMODULE_SELECTOR_NOT_FOUND

```solidity
string constant GUARDIANMODULE_SELECTOR_NOT_FOUND = "GM5"
```

### GUARDIANMODULE_ZERO_ADDRESS

```solidity
string constant GUARDIANMODULE_ZERO_ADDRESS = "GM6"
```

### KROLESBASE_ALREADY_INITIALIZED

```solidity
string constant KROLESBASE_ALREADY_INITIALIZED = "KB1"
```

### KROLESBASE_WRONG_ROLE

```solidity
string constant KROLESBASE_WRONG_ROLE = "KB2"
```

### KROLESBASE_ZERO_ADDRESS

```solidity
string constant KROLESBASE_ZERO_ADDRESS = "KB3"
```

### KROLESBASE_NOT_INITIALIZED

```solidity
string constant KROLESBASE_NOT_INITIALIZED = "KB4"
```

### KROLESBASE_ZERO_AMOUNT

```solidity
string constant KROLESBASE_ZERO_AMOUNT = "KB5"
```

### KROLESBASE_TRANSFER_FAILED

```solidity
string constant KROLESBASE_TRANSFER_FAILED = "KB6"
```

### KSTAKINGVAULT_INSUFFICIENT_BALANCE

```solidity
string constant KSTAKINGVAULT_INSUFFICIENT_BALANCE = "SV1"
```

### KSTAKINGVAULT_IS_PAUSED

```solidity
string constant KSTAKINGVAULT_IS_PAUSED = "SV2"
```

### KSTAKINGVAULT_NOT_INITIALIZED

```solidity
string constant KSTAKINGVAULT_NOT_INITIALIZED = "SV3"
```

### KSTAKINGVAULT_REQUEST_NOT_FOUND

```solidity
string constant KSTAKINGVAULT_REQUEST_NOT_FOUND = "SV4"
```

### KSTAKINGVAULT_VAULT_CLOSED

```solidity
string constant KSTAKINGVAULT_VAULT_CLOSED = "SV5"
```

### KSTAKINGVAULT_VAULT_SETTLED

```solidity
string constant KSTAKINGVAULT_VAULT_SETTLED = "SV6"
```

### KSTAKINGVAULT_WRONG_ROLE

```solidity
string constant KSTAKINGVAULT_WRONG_ROLE = "SV7"
```

### KSTAKINGVAULT_ZERO_ADDRESS

```solidity
string constant KSTAKINGVAULT_ZERO_ADDRESS = "SV8"
```

### KSTAKINGVAULT_ZERO_AMOUNT

```solidity
string constant KSTAKINGVAULT_ZERO_AMOUNT = "SV9"
```

### KSTAKINGVAULT_BATCH_LIMIT_REACHED

```solidity
string constant KSTAKINGVAULT_BATCH_LIMIT_REACHED = "SV10"
```

### KSTAKINGVAULT_MAX_TOTAL_ASSETS_REACHED

```solidity
string constant KSTAKINGVAULT_MAX_TOTAL_ASSETS_REACHED = "SV11"
```

### KSTAKINGVAULT_BATCH_NOT_VALID

```solidity
string constant KSTAKINGVAULT_BATCH_NOT_VALID = "SV12"
```

### KTOKEN_IS_PAUSED

```solidity
string constant KTOKEN_IS_PAUSED = "T1"
```

### KTOKEN_TRANSFER_FAILED

```solidity
string constant KTOKEN_TRANSFER_FAILED = "T2"
```

### KTOKEN_ZERO_ADDRESS

```solidity
string constant KTOKEN_ZERO_ADDRESS = "T3"
```

### KTOKEN_ZERO_AMOUNT

```solidity
string constant KTOKEN_ZERO_AMOUNT = "T4"
```

### KTOKEN_WRONG_ROLE

```solidity
string constant KTOKEN_WRONG_ROLE = "T5"
```

### VAULTBATCHES_NOT_CLOSED

```solidity
string constant VAULTBATCHES_NOT_CLOSED = "VB1"
```

### VAULTBATCHES_VAULT_CLOSED

```solidity
string constant VAULTBATCHES_VAULT_CLOSED = "VB2"
```

### VAULTBATCHES_VAULT_SETTLED

```solidity
string constant VAULTBATCHES_VAULT_SETTLED = "VB3"
```

### VAULTCLAIMS_BATCH_NOT_SETTLED

```solidity
string constant VAULTCLAIMS_BATCH_NOT_SETTLED = "VC1"
```

### VAULTCLAIMS_INVALID_BATCH_ID

```solidity
string constant VAULTCLAIMS_INVALID_BATCH_ID = "VC2"
```

### VAULTCLAIMS_NOT_BENEFICIARY

```solidity
string constant VAULTCLAIMS_NOT_BENEFICIARY = "VC4"
```

### VAULTCLAIMS_REQUEST_NOT_PENDING

```solidity
string constant VAULTCLAIMS_REQUEST_NOT_PENDING = "VC5"
```

### VAULTFEES_FEE_EXCEEDS_MAXIMUM

```solidity
string constant VAULTFEES_FEE_EXCEEDS_MAXIMUM = "VF1"
```

### VAULTFEES_INVALID_TIMESTAMP

```solidity
string constant VAULTFEES_INVALID_TIMESTAMP = "VF2"
```

### VAULTADAPTER_EXPIRED_SIGNATURE

```solidity
string constant VAULTADAPTER_EXPIRED_SIGNATURE = "VA1"
```

### VAULTADAPTER_INVALID_SIGNATURE

```solidity
string constant VAULTADAPTER_INVALID_SIGNATURE = "VA2"
```

### VAULTADAPTER_ZERO_ADDRESS

```solidity
string constant VAULTADAPTER_ZERO_ADDRESS = "VA3"
```

### VAULTADAPTER_WRONG_ROLE

```solidity
string constant VAULTADAPTER_WRONG_ROLE = "VA4"
```

### VAULTADAPTER_IS_PAUSED

```solidity
string constant VAULTADAPTER_IS_PAUSED = "VA5"
```

### VAULTADAPTER_NOT_INITIALIZED

```solidity
string constant VAULTADAPTER_NOT_INITIALIZED = "VA6"
```

### VAULTADAPTER_ZERO_AMOUNT

```solidity
string constant VAULTADAPTER_ZERO_AMOUNT = "VA7"
```

### VAULTADAPTER_TRANSFER_FAILED

```solidity
string constant VAULTADAPTER_TRANSFER_FAILED = "VA8"
```

### VAULTADAPTER_WRONG_ASSET

```solidity
string constant VAULTADAPTER_WRONG_ASSET = "VA9"
```

### VAULTADAPTER_WRONG_SELECTOR

```solidity
string constant VAULTADAPTER_WRONG_SELECTOR = "VA10"
```

### VAULTADAPTER_INVALID_NONCE

```solidity
string constant VAULTADAPTER_INVALID_NONCE = "VA11"
```

### VAULTADAPTER_WRONG_TARGET

```solidity
string constant VAULTADAPTER_WRONG_TARGET = "VA12"
```

### VAULTADAPTER_SELECTOR_NOT_ALLOWED

```solidity
string constant VAULTADAPTER_SELECTOR_NOT_ALLOWED = "VA13"
```

### VAULTADAPTER_ARRAY_MISMATCH

```solidity
string constant VAULTADAPTER_ARRAY_MISMATCH = "VA14"
```

### VAULTADAPTER_ZERO_ARRAY

```solidity
string constant VAULTADAPTER_ZERO_ARRAY = "VA15"
```

### EXECUTIONVALIDATOR_NOT_ALLOWED

```solidity
string constant EXECUTIONVALIDATOR_NOT_ALLOWED = "EV1"
```

### EXECUTIONVALIDATOR_ZERO_ADDRESS

```solidity
string constant EXECUTIONVALIDATOR_ZERO_ADDRESS = "EV2"
```

### EXECUTIONVALIDATOR_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER

```solidity
string constant EXECUTIONVALIDATOR_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER = "EV3"
```

### EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED

```solidity
string constant EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED = "EV4"
```

### EXECUTIONVALIDATOR_SOURCE_NOT_ALLOWED

```solidity
string constant EXECUTIONVALIDATOR_SOURCE_NOT_ALLOWED = "EV5"
```

### EXECUTIONVALIDATOR_SPENDER_NOT_ALLOWED

```solidity
string constant EXECUTIONVALIDATOR_SPENDER_NOT_ALLOWED = "EV6"
```

### EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED

```solidity
string constant EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED = "EV7"
```

### KREMOTEREGISTRY_NOT_ALLOWED

```solidity
string constant KREMOTEREGISTRY_NOT_ALLOWED = "RR1"
```

### KREMOTEREGISTRY_ZERO_ADDRESS

```solidity
string constant KREMOTEREGISTRY_ZERO_ADDRESS = "RR2"
```

### KREMOTEREGISTRY_ZERO_SELECTOR

```solidity
string constant KREMOTEREGISTRY_ZERO_SELECTOR = "RR3"
```

### KREMOTEREGISTRY_SELECTOR_ALREADY_SET

```solidity
string constant KREMOTEREGISTRY_SELECTOR_ALREADY_SET = "RR4"
```

### KREMOTEREGISTRY_SELECTOR_NOT_FOUND

```solidity
string constant KREMOTEREGISTRY_SELECTOR_NOT_FOUND = "RR5"
```

### KTOKENFACTORY_ZERO_ADDRESS

```solidity
string constant KTOKENFACTORY_ZERO_ADDRESS = "F1"
```

### KTOKENFACTORY_DEPLOYMENT_FAILED

```solidity
string constant KTOKENFACTORY_DEPLOYMENT_FAILED = "F2"
```

### KTOKENFACTORY_WRONG_ROLE

```solidity
string constant KTOKENFACTORY_WRONG_ROLE = "F3"
```

