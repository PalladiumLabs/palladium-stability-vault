pragma solidity ^0.8.12;

library AccountBalanceLib {
    /// Checks that either BOTH, FROM, or TO accounts do not have negative balances
    enum BalanceCheckFlag {
        Both,
        From,
        To,
        None
    }
}

interface IDepositWithdrawalRouter {
    enum EventFlag {
        None,
        Borrow
    }

    /**
     * @param _isolationModeMarketId The market ID of the isolation mode token vault
     *                               (0 if not using isolation mode)
     * @param _toAccountNumber       The account number to deposit into
     * @param _marketId              The ID of the market being deposited
     * @param _amountWei             The amount in Wei to deposit. Use type(uint256).max to deposit
     *                               mgs.sender's entire balance
     * @param _eventFlag             Flag indicating if this deposit should emit
     *                               special events (e.g. opening a borrow position)
     */
    function depositWei(
        uint256 _isolationModeMarketId,
        uint256 _toAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        EventFlag _eventFlag
    ) external;

    /**
     * @param _isolationModeMarketId The market ID of the isolation mode token vault
     *                               (0 if not using isolation mode)
     * @param _fromAccountNumber     The account number to withdraw from
     * @param _marketId              The ID of the market being withdrawn
     * @param _amountWei             The amount in Wei to withdraw. Use type(uint256).max
     *                               to withdraw entire balance
     * @param _balanceCheckFlag      Flag indicating how to validate account balances after
     *                               withdrawal
     */
    function withdrawWei(
        uint256 _isolationModeMarketId,
        uint256 _fromAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag
    ) external;
}
