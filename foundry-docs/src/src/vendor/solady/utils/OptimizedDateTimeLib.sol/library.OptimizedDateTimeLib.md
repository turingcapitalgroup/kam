# OptimizedDateTimeLib
[Git Source](https://github.com/VerisLabs/KAM/blob/23d03b05f3e96964e57bd3b573e4ae3d882ae057/src/vendor/solady/utils/OptimizedDateTimeLib.sol)

**Author:**
Solady (https://github.com/vectorized/solady/blob/main/src/utils/DateTimeLib.sol)

Library for date time operations.

Some functions were removed


## Functions
### dateToEpochDay

Returns the number of days since 1970-01-01 from (`year`,`month`,`day`).
See: https://howardhinnant.github.io/date_algorithms.html
Note: Inputs outside the supported ranges result in undefined behavior.
Use {isSupportedDate} to check if the inputs are supported.


```solidity
function dateToEpochDay(uint256 year, uint256 month, uint256 day) internal pure returns (uint256 epochDay);
```

### epochDayToDate

Returns (`year`,`month`,`day`) from the number of days since 1970-01-01.
Note: Inputs outside the supported ranges result in undefined behavior.
Use {isSupportedDays} to check if the inputs is supported.


```solidity
function epochDayToDate(uint256 epochDay) internal pure returns (uint256 year, uint256 month, uint256 day);
```

### timestampToDate

Returns (`year`,`month`,`day`) from the given unix timestamp.
Note: Inputs outside the supported ranges result in undefined behavior.
Use {isSupportedTimestamp} to check if the inputs are supported.


```solidity
function timestampToDate(uint256 timestamp) internal pure returns (uint256 year, uint256 month, uint256 day);
```

### dateTimeToTimestamp

Returns the unix timestamp from
(`year`,`month`,`day`,`hour`,`minute`,`second`).
Note: Inputs outside the supported ranges result in undefined behavior.
Use {isSupportedDateTime} to check if the inputs are supported.


```solidity
function dateTimeToTimestamp(uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second)
    internal
    pure
    returns (uint256 result);
```

### timestampToDateTime

Returns (`year`,`month`,`day`,`hour`,`minute`,`second`)
from the given unix timestamp.
Note: Inputs outside the supported ranges result in undefined behavior.
Use {isSupportedTimestamp} to check if the inputs are supported.


```solidity
function timestampToDateTime(uint256 timestamp)
    internal
    pure
    returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);
```

### daysInMonth

Returns number of days in given `month` of `year`.


```solidity
function daysInMonth(uint256 year, uint256 month) internal pure returns (uint256 result);
```

### isLeapYear

Returns if the `year` is leap.


```solidity
function isLeapYear(uint256 year) internal pure returns (bool leap);
```

