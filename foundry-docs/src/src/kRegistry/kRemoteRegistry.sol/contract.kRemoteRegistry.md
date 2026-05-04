# kRemoteRegistry
[Git Source](https://github.com/turingcapitalgroup/kam/blob/fd8b703a6216c4a6a7aeca93ae8d60f4c197f8a2/src/kRegistry/kRemoteRegistry.sol)

**Inherits:**
[IkRemoteRegistry](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/IkRemoteRegistry.sol/interface.IkRemoteRegistry.md), [ExecutionGuardianModule](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/kRegistry/modules/ExecutionGuardianModule.sol/contract.ExecutionGuardianModule.md), [Initializable](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/solady/utils/Initializable.sol/abstract.Initializable.md), [UUPSUpgradeable](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/solady/utils/UUPSUpgradeable.sol/abstract.UUPSUpgradeable.md)

Lightweight registry for cross-chain metaWallet adapter validation

Simplified version of kRegistry for deployment on chains where the full KAM protocol is not deployed.
Provides adapter permission management and call validation for SmartAdapterAccount contracts.
Inherits executor permission logic from ExecutionGuardianModule, wrapping it with Ownable access control.


## Functions
### constructor

Disables initializers to prevent implementation contract initialization


```solidity
constructor() ;
```

### initialize

Initializes the registry with an owner


```solidity
function initialize(address _owner) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|The owner address who can configure the registry|


### setAllowedSelector

Sets whether an executor can call a specific selector on a target

Only callable by owner. Overrides ExecutionGuardianModule to use Ownable access control.


```solidity
function setAllowedSelector(
    address _executor,
    address _target,
    uint8 _targetType,
    bytes4 _selector,
    bool _isAllowed
)
    external
    override(ExecutionGuardianModule, IExecutionGuardian);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_targetType`|`uint8`|The target type classification|
|`_selector`|`bytes4`|The function selector|
|`_isAllowed`|`bool`|Whether the selector should be allowed|


### setExecutionValidator

Sets an execution validator for an executor-target-selector combination

Only callable by owner. The selector must already be allowed.


```solidity
function setExecutionValidator(
    address _executor,
    address _target,
    bytes4 _selector,
    address _executionValidator
)
    external
    override(ExecutionGuardianModule, IExecutionGuardian);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|
|`_executionValidator`|`address`|The execution validator contract address (address(0) to remove)|


### _authorizeUpgrade

Authorizes contract upgrades

Only callable by owner


```solidity
function _authorizeUpgrade(address _newImplementation) internal view override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newImplementation`|`address`|New implementation address|


### contractName

Returns the human-readable name identifier for this contract type

Used for contract identification and logging purposes. The name should be consistent
across all versions of the same contract type. This enables external systems and other
contracts to identify the contract's purpose and role within the protocol ecosystem.


```solidity
function contractName() external pure returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract name as a string (e.g., "kMinter", "kAssetRouter", "kRegistry")|


### contractVersion

Returns the version identifier for this contract implementation

Used for upgrade management and compatibility checking within the protocol. The version
string should follow semantic versioning (e.g., "1.0.0") to clearly indicate major, minor,
and patch updates. This enables the protocol governance and monitoring systems to track
deployed versions and ensure compatibility between interacting components.


```solidity
function contractVersion() external pure returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract version as a string following semantic versioning (e.g., "1.0.0")|


