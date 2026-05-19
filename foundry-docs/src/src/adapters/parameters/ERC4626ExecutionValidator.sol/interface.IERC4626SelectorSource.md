# IERC4626SelectorSource
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/adapters/parameters/ERC4626ExecutionValidator.sol)


## Functions
### deposit


```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
```

### mint


```solidity
function mint(uint256 shares, address receiver) external returns (uint256 assets);
```

### withdraw


```solidity
function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
```

### redeem


```solidity
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
```

