use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<T> {
    // Core functions
    fn execute(ref self: T);
    fn stake(ref self: T, amount: u256);
    fn withdraw(ref self: T);
    // Getters
    fn balances(self: @T, account: ContractAddress) -> u256;
    fn completed(self: @T) -> bool;
    fn deadline(self: @T) -> u64;
    fn example_external_contract(self: @T) -> ContractAddress;
    fn open_for_withdraw(self: @T) -> bool;
    fn eth_token_dispatcher(self: @T) -> IERC20CamelDispatcher;
    fn threshold(self: @T) -> u256;
    fn total_balance(self: @T) -> u256;
    fn time_left(self: @T) -> u64;
}

#[starknet::contract]
pub mod Staker {
    use contracts::ExampleExternalContract::{
        IExampleExternalContractDispatcher, IExampleExternalContractDispatcherTrait,
    };
    use starknet::storage::Map;
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};
    use super::{ContractAddress, IERC20CamelDispatcher, IERC20CamelDispatcherTrait, IStaker};

    const THRESHOLD: u256 = 1000000000000000000; // ONE_ETH_IN_WEI: 10 ^ 18;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Stake: Stake,
    }

    #[derive(Drop, starknet::Event)]
    struct Stake {
        #[key]
        sender: ContractAddress,
        amount: u256,
    }

    #[storage]
    struct Storage {
        eth_token_dispatcher: IERC20CamelDispatcher,
        balances: Map<ContractAddress, u256>,
        deadline: u64,
        open_for_withdraw: bool,
        external_contract_address: ContractAddress,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        eth_contract: ContractAddress,
        external_contract_address: ContractAddress,
    ) {
        self.eth_token_dispatcher.write(IERC20CamelDispatcher { contract_address: eth_contract });
        self.external_contract_address.write(external_contract_address);
        // ToDo Checkpoint 2: Set the deadline to 60 seconds from now. Implement your code here.
        self.deadline.write(get_block_timestamp() + 259200)
    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
        // ToDo Checkpoint 1: Implement your `stake` function here
        // ToDo Checkpoint 3: Assert that the staking period has not ended
        fn stake(
            ref self: ContractState, amount: u256,
        ) { // Note: In UI and Debug contract `sender` should call `approve`` before to `transfer` the amount to the staker contract
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();
            assert(current_time < deadline, 'Staking period has ended');
            // Get token contract dispatcher
            let token = self.eth_token_dispatcher.read();

            // Transfer tokens from caller to this contract
            let contract_address = get_contract_address();
            token.transferFrom(caller, contract_address, amount);

            // Update user balance
            let prev_balance = self.balances.read(caller);
            let new_balance = prev_balance + amount;
            self.balances.write(caller, new_balance);

            // Update total balance of contract
            let contract_prev_balance = self.balances.read(contract_address);
            let contract_new_balance = contract_prev_balance + amount;
            self.balances.write(contract_address, contract_new_balance);

            // Emit stake event
            self.emit(Stake { sender: caller, amount });
        }

        // Function to execute the transfer or allow withdrawals after the deadline
        // ToDo Checkpoint 2: Implement your `execute` function here
        // In this implimentation, we should call the `complete_transfer` function if the staked
        // amount is greater than or equal to the threshold Otherwise, we should call
        // `open_for_withdraw` function ToDo Checkpoint 3: Assert that the staking period has ended
        // ToDo Checkpoint 3: Protect the function calling `not_completed` function before the
        // execution
        fn execute(ref self: ContractState) {
            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();
            assert(current_time >= deadline, 'Staking period not ended');

            self.not_completed();

            let token = self.eth_token_dispatcher.read();
            let staked_amount = IERC20CamelDispatcherTrait::balanceOf(
                token, get_contract_address(),
            );

            if staked_amount >= THRESHOLD {
                self.complete_transfer(staked_amount);
            } else {
                self.open_for_withdraw.write(true);
            }
        }

        // ToDo Checkpoint 3: Implement your `withdraw` function here
        fn withdraw(ref self: ContractState) {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();

            // 1. Ensure deadline passed
            assert(current_time >= deadline, 'Staking period not ended');

            // 2. Ensure withdrawals are open
            let open = self.open_for_withdraw.read();
            assert(open == true, 'Withdrawals not allowed');

            // 3. Get caller balance
            let caller_balance = self.balances.read(caller);
            assert(caller_balance > 0, 'No balance to withdraw');

            // 4. Transfer tokens back to caller
            let token = self.eth_token_dispatcher.read();
            IERC20CamelDispatcherTrait::transfer(token, caller, caller_balance);

            // 5. Update balances
            self.balances.write(caller, 0);

            let contract_address = get_contract_address();
            let contract_balance = self.balances.read(contract_address);
            let updated_contract_balance = contract_balance - caller_balance;
            self.balances.write(contract_address, updated_contract_balance);
        }

        fn balances(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn total_balance(self: @ContractState) -> u256 {
            self.balances.read(get_contract_address())
        }

        fn deadline(self: @ContractState) -> u64 {
            self.deadline.read()
        }

        fn threshold(self: @ContractState) -> u256 {
            THRESHOLD
        }

        fn eth_token_dispatcher(self: @ContractState) -> IERC20CamelDispatcher {
            self.eth_token_dispatcher.read()
        }

        fn open_for_withdraw(self: @ContractState) -> bool {
            self.open_for_withdraw.read()
        }

        fn example_external_contract(self: @ContractState) -> ContractAddress {
            self.external_contract_address.read()
        }
        // Read Function to check if the external contract is completed.
        // ToDo Checkpoint 3: Implement your completed function here
        fn completed(self: @ContractState) -> bool {
            let dispatcher = IExampleExternalContractDispatcher {
                contract_address: self.external_contract_address.read(),
            };

            IExampleExternalContractDispatcherTrait::completed(dispatcher)
        }
        // ToDo Checkpoint 2: Implement your time_left function here
        fn time_left(self: @ContractState) -> u64 {
            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();

            if current_time >= deadline {
                0
            } else {
                deadline - current_time
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // ToDo Checkpoint 2: Implement your complete_transfer function here
        // This function should be called after the deadline has passed and the staked amount is
        // greater than or equal to the threshold You have to call/use this function in the above
        // `execute` function This function should call the `complete` function of the external
        // contract and transfer the staked amount to the external contract
        fn complete_transfer(
            ref self: ContractState, amount: u256,
        ) { // Note: Staker contract should approve to transfer the staked_amount to the external contract
            let external_addr = self.external_contract_address.read();
            let token = self.eth_token_dispatcher.read();

            IERC20CamelDispatcherTrait::approve(token, external_addr, amount);

            let external_dispatcher = IExampleExternalContractDispatcher {
                contract_address: external_addr,
            };
            IExampleExternalContractDispatcherTrait::complete(external_dispatcher);
        }
        // ToDo Checkpoint 3: Implement your not_completed function here
        fn not_completed(ref self: ContractState) {
            let external_addr = self.external_contract_address.read();
            let dispatcher = IExampleExternalContractDispatcher { contract_address: external_addr };

            let is_completed = IExampleExternalContractDispatcherTrait::completed(dispatcher);
            assert(is_completed == false, 'Already completed');
        }
    }
}
