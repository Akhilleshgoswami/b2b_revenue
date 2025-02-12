module kgen::B2BRevenueV1 {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin;
    use std::vector;
    use std::table;
    use aptos_std::string;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::primary_fungible_store;
    use std::debug::print;
    use aptos_framework::account::{Self};
    const E_NOT_WHITELISTED: u64 = 1001;
    const E_NOT_ADMIN: u64 = 1002;
    const E_INVALID_AMOUNT: u64 = 1003;
    const E_INSUFFICIENT_BALANCE: u64 = 1004;
    const CORE_ADDRESS: address = @kgen;
     
    const SEED: vector<u8> = b"b2c-revenue";
    struct Whitelist has key {
        accounts: vector<address>,
        admin: address,
        revenue_account_cap: account::SignerCapability,
    }

// wallet_addresse => token_address=>value
    struct Balances has key {
        balances: table::Table<address, u64>,
        tokenbalances: table::Table<address, u64>,
    }
    inline fun get_metadata_object(object: address): Object<Metadata> {
        object::address_to_object<Metadata>(object)
    }

    public entry fun initialize(admin: &signer) {
        let caller_address = signer::address_of(admin);
        assert!(signer::address_of(admin) == CORE_ADDRESS, E_NOT_ADMIN);
        let (_, treasury_account_cap) = account::create_resource_account(admin, SEED);
        move_to(admin, Whitelist {
            revenue_account_cap:treasury_account_cap,
            admin: caller_address,
            accounts: vector[]
        });

        move_to(admin, Balances { balances: table::new<address, u64>() ,tokenbalances : table::new<address, u64>()  });
    }
    fun get_resource_account_sign(): signer acquires Whitelist {
        account::create_signer_with_capability(
            &borrow_global_mut<Whitelist>(@kgen).revenue_account_cap
        )
    } 

struct WhitelistToken has key, store, drop {
    isWhiteListed: bool,
}

struct WhitelistTokens has key, store {
    tokens: table::Table<address, WhitelistToken>,
}

public entry fun add_whitelist_token(admin: &signer, token: address) acquires WhitelistTokens,Whitelist {
    let caller_address = signer::address_of(admin);
    assert!(is_admin(caller_address), E_NOT_ADMIN);

    if (!exists<WhitelistTokens>(caller_address)) {
        move_to(admin, WhitelistTokens { tokens: table::new<address, WhitelistToken>() });
    };

    let whitelist_ref = borrow_global_mut<WhitelistTokens>(caller_address);

    table::upsert(
        &mut whitelist_ref.tokens,
        token,
        WhitelistToken { isWhiteListed: true }
    );
}


public fun is_token_whitelisted(token: address): bool acquires WhitelistTokens {
    if (!exists<WhitelistTokens>(@kgen)) {
        return false;
    };

    let whitelist_ref = borrow_global<WhitelistTokens>(@kgen);
    
    if (!table::contains(&whitelist_ref.tokens, token)) {
        return false;
    };
    
    let token_data = table::borrow(&whitelist_ref.tokens, token);
    token_data.isWhiteListed
}

    public entry fun add_whitelist_address(admin: &signer, account: address) acquires Whitelist {
        let caller_address = signer::address_of(admin);
        assert!(is_admin(caller_address), E_NOT_ADMIN);
        let whitelist_ref = borrow_global_mut<Whitelist>(CORE_ADDRESS);
        whitelist_ref.accounts.push_back(account);
    }

    public fun get_whitelist(admin: &signer): vector<address> acquires Whitelist {
        let whitelist_ref = borrow_global<Whitelist>(CORE_ADDRESS);
        whitelist_ref.accounts
    }

    public entry fun remove_from_whitelist(admin: &signer, account: address) acquires Whitelist {
        let caller_address = signer::address_of(admin);
        assert!(is_admin(caller_address), E_NOT_ADMIN);
        let whitelist_ref = borrow_global_mut<Whitelist>(CORE_ADDRESS);
        let  index = 0;
        let  found = false;
        let length = vector::length(&whitelist_ref.accounts);

        let  i = index;
        while (i < length) {
            if (*vector::borrow(&whitelist_ref.accounts, i) == account) {
                found = true;
                break;
            };
            i = i + 1;
        };
        assert!(found, E_INVALID_AMOUNT);
        vector::swap_remove(&mut whitelist_ref.accounts, i);
    }

public entry fun deposit(user: &signer, token: address, amount: u64) acquires Balances , Whitelist,WhitelistTokens{
    let caller_address = signer::address_of(user);
    assert!(amount > 0, E_INVALID_AMOUNT);
   assert!(is_token_whitelisted(token),E_NOT_WHITELISTED);
    let balance_ref = borrow_global_mut<Balances>(CORE_ADDRESS);
    let current_balance = if (table::contains(&balance_ref.balances, caller_address)) {
        *table::borrow_mut(&mut balance_ref.balances, caller_address)
    } else {
        0
    };
    let token_balance =  if (table::contains(&balance_ref.tokenbalances, token)) {
        *table::borrow_mut(&mut balance_ref.tokenbalances, token)
    } else {
        0
    };
    let treasury = &get_resource_account_sign();
    primary_fungible_store::transfer(
        user,
        get_metadata_object(token),
        signer::address_of(treasury), 
        amount
    );
    let new_balance = current_balance + amount;
    let new_token_balance = token_balance + amount;
     if (table::contains(&balance_ref.tokenbalances, token)) {
        *table::borrow_mut(&mut balance_ref.tokenbalances, token) = new_token_balance;
    } else {
        table::add(&mut balance_ref.tokenbalances, token, new_token_balance);
    };
    if (table::contains(&balance_ref.balances, caller_address)) {
        *table::borrow_mut(&mut balance_ref.balances, caller_address) = new_balance;
    } else {
        table::add(&mut balance_ref.balances, caller_address, new_balance);
    };
}

public entry fun withdraw(user: &signer, token: address, amount: u64,to:address) acquires Balances, Whitelist,WhitelistTokens {
    let caller_address = signer::address_of(user);
    assert!(amount > 0, E_INVALID_AMOUNT);
    assert!(is_admin(caller_address), E_NOT_ADMIN);
    assert!(is_token_whitelisted(token),E_NOT_WHITELISTED);
    let balance_ref = borrow_global_mut<Balances>(CORE_ADDRESS);
    let current_token_balance = table::borrow_mut(&mut balance_ref.tokenbalances, token);
    assert!(*current_token_balance >= amount, E_INSUFFICIENT_BALANCE);
    *current_token_balance = *current_token_balance - amount;
    let treasury = &get_resource_account_sign();
    primary_fungible_store::transfer(
        treasury,
        get_metadata_object(token),
        to,
        amount
    );
}
#[view]
fun is_admin(caller: address): bool acquires Whitelist {
        let whitelist_ref = borrow_global<Whitelist>(CORE_ADDRESS);
        whitelist_ref.admin == caller
    }

#[view]
public fun get_admin_balance(user: address, token_address: address): u64 acquires Balances {
    let balances_ref = borrow_global<Balances>(CORE_ADDRESS);
    if (!table::contains(&balances_ref.balances, user)) {
        return 0;
    };
    let balance_ref = table::borrow(&balances_ref.balances, user);
    *balance_ref
}
// not used anymore 
#[view]
public fun get_token_balance(user: address, token_address: address): u64 acquires Balances {
    let balances_ref = borrow_global<Balances>(CORE_ADDRESS);
    if (!table::contains(&balances_ref.tokenbalances, token_address)) {
        return 0;
    };
    let balance_ref = table::borrow(&balances_ref.tokenbalances, token_address);
    *balance_ref
}
#[view]
public fun get_token_balance_v1(token_address: address): u64 acquires Balances {
    let balances_ref = borrow_global<Balances>(CORE_ADDRESS);
    if (!table::contains(&balances_ref.tokenbalances, token_address)) {
        return 0;
    };
    let balance_ref = table::borrow(&balances_ref.tokenbalances, token_address);
    *balance_ref
}
}

