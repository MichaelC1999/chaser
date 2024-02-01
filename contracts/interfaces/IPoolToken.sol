import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPoolToken is IERC20 {
    /**
     * @dev Mints `amount` tokens to `account`.
     *
     * Requirements:
     * - the caller must have the necessary privilege to mint tokens.
     *
     * @param account The address of the beneficiary that will receive the minted tokens.
     * @param amount The amount of tokens to be minted.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @dev Burns `amount` tokens from `account`.
     *
     * Requirements:
     * - the caller must have the necessary privilege to burn tokens.
     * - `account` must have at least `amount` tokens.
     *
     * @param account The address of the holder whose tokens will be burnt.
     * @param amount The amount of tokens to be burnt.
     */
    function burn(address account, uint256 amount) external;
}
