# Adapter-SDK

In order to provide as many 4626-compliant adapters as possible for our customers, we have standardized our testing and development procedures to conform to a set of defined tests and standards. We have provided this list of requirements so that anyone can build and submit an adapter to to the Resonate Protocol. 

Anyone wishing to create a 4626-compliant vault adapter can build it and submit it for approval to Resonate provided it meets the required standards and passes the approved tests, defined below.

1. The Adapter must comply completely with the 4626-Vault-Standard
2. The adapter must expose the 4626-interface to the end-user, while providing the same functionality as an underlying defi-protocol.
  Example: ABC Protocol Vault allows you to deposit tokens using the depositTokens(uint) function, and withdraw using the withdrawTokens(uint) function. The adapter should accept tokens through its mint and deposit functions, and then pass them to the underlying vault's deposit functionality
The adapter should hold all of the shares given out by the underlying vault, instead issuing its own shares to those who deposit. If the vault is yUSDC, the adapter should hold all the yUSDC, giving its ownyaUSDC to the user.

3. The adapter should be permissionless, allowing anyone to interact outside of Resonate.
Our goal is to provide not only increased functionality for Resonate pools, but to further push for the adoption of 4626 by releasing these adapters as public-goods.

4. The adapter should not take any fees, but should be aware of any fees taken by the underlying yield-bearing-vault.

5. All adapters will be open-sourced.

## Required Tests

To be included in Resonate, your adapter must pass our defined testing standards. We have provided a skeleton, but as every adapter functions differently, you will need to write them yourselves. We recommend foundry. Your testing files must implement the `GenericAdapterTest` Interface provided below.

```
interface GenericAdapterTest {

    function testDeposit(uint256 amount) external;

    function testMint(uint amount) external;

    function testWithdraw(uint amount, uint withdrawAmount) external;

    function testRedeem(uint amount, uint redeemAmount) external;

    function testRoundTrip_deposit_withdraw(uint amount) external;
    
    function testRoundTrip_mint_redeem(uint amount) external;

    function testWithdrawAllowance(uint amount) external;

    function testFailWithdrawAllowance(uint amount) external;

    function testMiscViewMethods(uint amount) external;
}
```

### testDeposit(uint256 amount)
1. Test should allow a user to deposit amount of tokens into the vault successfully after approving the adapter to spend their tokens
3. The test should use `previewDeposit()` on the amount before depositing. Shares returned from `deposit(amount) >= previewDeposit(amount)`
3. All tokens specified by the deposit amount should be moved from the user to the underlying Vault
4. The vault-share balance of the adapter should increase, and the vault-balance of Token should as well.

### testMint(uint amount)
1. The user should be able to mint amount shares from the adapter, depositing the minimum number of tokens into the adapter to accomplish this.
2. The test should use `previewMint()` on the amount before minting. Shares returned from `mint(amount) <= previewMint(amount)`
3. The exact number of requested shares should be minted by the adapter to the user.

### testWithdraw(uint amount, uint withdrawAmount)
1. The test should first deposit tokens into the adapter, and then specify an amount <= than the original amount to withdraw.
2. The test should use `previewWithdraw` where the amount of shares actually burnt by `withdraw()` <= `previewWithdraw()`
3. Should meet the above specifications for `deposit()`

### testRedeem(uint amount, uint redeemAmount)
1. The test should first mint shares from adapter, and then specify an amount of shares <= than the original amount to redeem.
2. The test should use `previewWithdraw()` where the amount of shares actually burnt by `redeem() >= previewRedeem()`
3. Should meet the above specifications of `mint()`

### testRoundTrip_deposit_withdraw(uint amount)
1. Test should deposit amount of tokens into the vault adapter, meeting all the requirements of the `testDeposit()` test
2. Test should withdraw **all** of those tokens back to the user, meeting the specifications of `testWithdraw()`
3. Tests should account for any fees taken, and revert if minimum amount of tokens cannot be returned to the user. 

### testRoundTrip_mint_redeem(uint amount)
1. Test should mint amount of shares from the vault adapter, meeting all the requirements of `testMint()`
2. Test should redeem all of those shares back to the user, meeting the specifications of `testRedeem()`

### testWithdrawAllowance(uint amount)
1. Test should have user Alice deposit amount tokens into the adapter. 
2. Alice should give permissions to user Bob to withdraw those tokens. Since ERC-4626 is also ERC-20, this should be done with a simple approval call to the adapter.
3. Bob should be able to withdraw amount tokens from the adapter, meeting the specifications of `testWithdraw()`. The allowance of Bob should be calculated by converting between assets and shares using `convertToAssets(shares)` and `convertToShares(assets)`

### testFailWithdrawAllowance(uint amount)
1. Test should have user Alice deposit amount tokens into the adapter. 
2. User Bob should attempt to withdraw these tokens, but should revert since they have not been approved to do so by owner Alice.

### testMiscViewMethods(uint amount)
1. Test should have alice deposit amount tokens into the vault.
2. Test should invoke all remaining view-only methods in the adapter for accuracy.
    1. `maxMint()`
    2. `maxDeposit()`
    3. `maxWithdraw()`
    4. `maxRedeem()`

*Each method should execute without reverting, and the return values before and after should be different.
