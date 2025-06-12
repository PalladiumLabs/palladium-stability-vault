pragma solidity ^0.8.9;

library Account {
    // Represents the unique key that specifies an account
    struct Info {
        address owner; // The address that owns the account
        uint256 number; // A nonce that allows a single address to control many accounts
    }
}

library Types {
    struct Par {
        bool sign; // true if positive
        uint128 value;
    }

    struct Wei {
        bool sign; // true if positive
        uint128 value;
    }
}

interface IDolomiteMargin {
    function getMarketIdByTokenAddress(address token) external view returns (uint256);

    function getAccountWei(Account.Info calldata account, uint256 marketId) external view returns (Types.Wei memory);
}
