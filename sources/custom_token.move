module custom_token_addr::main {
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_framework::object::ExtendRef;
    use aptos_std::string_utils::{to_string};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use std::error;
    use std::option;
    use std::signer::address_of;
    use std::signer;
    use std::string::{Self, String};

    /// custom_token not available
    const ENOT_AVAILABLE: u64 = 1;
    /// name length exceeded limit
    const ENAME_LIMIT: u64 = 2;
    /// user already has custom_token
    const EUSER_ALREADY_HAS_CUSTOM_TOKEN: u64 = 3;

    // maximum health points: 5 hearts * 2 HP/heart = 10 HP
    const ENERGY_UPPER_BOUND: u64 = 10;
    const NAME_UPPER_BOUND: u64 = 40;

    struct CustomToken has key {
        name: String,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
    }

    #[event]
    struct MintCustomTokenEvent has drop, store {
        token_name: String,
        custom_token_name: String,
    }

    // We need a contract signer as the creator of the custom_token collection and custom_token token
    // Otherwise we need admin to sign whenever a new custom_token token is minted which is inconvenient
    struct ObjectController has key {
        // This is the extend_ref of the app object, not the extend_ref of collection object or token object
        // app object is the creator and owner of custom_token collection object
        // app object is also the creator of all custom_token token (NFT) objects
        // but owner of each token object is custom_token owner (i.e. user who mints custom_token)
        app_extend_ref: ExtendRef,
    }

    const APP_OBJECT_SEED: vector<u8> = b"CUSTOM_TOKEN";
    const COLLECTION_NAME: vector<u8> = b"CustomToken Collection";
    const COLLECTION_DESCRIPTION: vector<u8> = b"CustomToken Collection Description";
    const COLLECTION_URI: vector<u8> = b"https://otjbxblyfunmfblzdegw.supabase.co/storage/v1/object/public/custom_token/custom_token.png";
    // Body value range is [0, 4] inslusive
    const BODY_MAX_VALUE: u8 = 4;
    // Ear value range is [0, 5] inslusive
    const EAR_MAX_VALUE: u8 = 6;
    // Face value range is [0, 3] inslusive
    const FACE_MAX_VALUE: u8 = 3;

    // This function is only called once when the module is published for the first time.
    fun init_module(account: &signer) {
        let constructor_ref = object::create_named_object(
            account,
            APP_OBJECT_SEED,
        );
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let app_signer = &object::generate_signer(&constructor_ref);

        move_to(app_signer, ObjectController {
            app_extend_ref: extend_ref,
        });

        create_custom_token_collection(app_signer);
    }

    // ================================= Helper Functions ================================= //

    fun get_app_signer_addr(): address {
        object::create_object_address(&@custom_token_addr, APP_OBJECT_SEED)
    }

    fun get_app_signer(): signer acquires ObjectController {
        object::generate_signer_for_extending(&borrow_global<ObjectController>(get_app_signer_addr()).app_extend_ref)
    }

    // Create the collection that will hold all the CustomTokens
    fun create_custom_token_collection(creator: &signer) {
        let description = string::utf8(COLLECTION_DESCRIPTION);
        let name = string::utf8(COLLECTION_NAME);
        let uri = string::utf8(COLLECTION_URI);

        collection::create_unlimited_collection(
            creator,
            description,
            name,
            option::none(),
            uri,
        );
    }

    // ================================= Entry Functions ================================= //

    // Create an CustomToken token object
    public entry fun create_custom_token(
        user: &signer,
        name: String,
    ) acquires ObjectController {
        assert!(string::length(&name) <= NAME_UPPER_BOUND, error::invalid_argument(ENAME_LIMIT));

        let uri = string::utf8(COLLECTION_URI);
        let description = string::utf8(COLLECTION_DESCRIPTION);
        let user_addr = address_of(user);
        let token_name = to_string(&user_addr);

        assert!(!has_custom_token(user_addr), error::already_exists(EUSER_ALREADY_HAS_CUSTOM_TOKEN));

        let constructor_ref = token::create_named_token(
            &get_app_signer(),
            string::utf8(COLLECTION_NAME),
            description,
            token_name,
            option::none(),
            uri,
        );

        let token_signer = object::generate_signer(&constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);

        // initialize/set default CustomToken struct values
        let gotchi = CustomToken {
            name,
            mutator_ref,
            burn_ref,
        };

        move_to(&token_signer, gotchi);

        // Emit event for minting CustomToken token
        event::emit<MintCustomTokenEvent>(
            MintCustomTokenEvent {
                token_name,
                custom_token_name: name,
            },
        );

        object::transfer_with_ref(object::generate_linear_transfer_ref(&transfer_ref), address_of(user));
    }

    // Sets custom_token's name
    public entry fun set_name(owner: signer, name: String) acquires CustomToken {
        let owner_addr = signer::address_of(&owner);
        assert!(has_custom_token(owner_addr), error::unavailable(ENOT_AVAILABLE));
        assert!(string::length(&name) <= NAME_UPPER_BOUND, error::invalid_argument(ENAME_LIMIT));
        let token_address = get_custom_token_address(owner_addr);
        let gotchi = borrow_global_mut<CustomToken>(token_address);
        gotchi.name = name;
    }

    // ================================= View Functions ================================== //

    // Get reference to CustomToken token object (CAN'T modify the reference)
    #[view]
    public fun get_custom_token_address(creator_addr: address): (address) {
        let collection = string::utf8(COLLECTION_NAME);
        let token_name = to_string(&creator_addr);
        let creator_addr = get_app_signer_addr();
        let token_address = token::create_token_address(
            &creator_addr,
            &collection,
            &token_name,
        );

        token_address
    }

    // Get collection address (also known as collection ID) of custom_token collection
    // Collection itself is an object, that's why it has an address
    #[view]
    public fun get_custom_token_collection_address(): (address) {
        let collection_name = string::utf8(COLLECTION_NAME);
        let creator_addr = get_app_signer_addr();
        collection::create_collection_address(&creator_addr, &collection_name)
    }

    // Returns true if this address owns an CustomToken
    #[view]
    public fun has_custom_token(owner_addr: address): (bool) {
        let token_address = get_custom_token_address(owner_addr);

        exists<CustomToken>(token_address)
    }

    // ================================= Unit Tests ================================== //

    // Setup testing environment
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test_only]
    use std::string::utf8;

    #[test_only]
    fun setup_test(aptos: &signer, account: &signer, creator: &signer) {
        // create a fake account (only for testing purposes)
        create_account_for_test(signer::address_of(creator));
        create_account_for_test(signer::address_of(account));

        timestamp::set_time_has_started_for_testing(aptos);
        init_module(account);
    }

    // Test creating an CustomToken
    #[test(aptos = @0x1, account = @custom_token_addr, creator = @0x123)]
    fun test_create_custom_token(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires ObjectController {
        setup_test(aptos, account, creator);

        create_custom_token(creator, utf8(b"test"));

        let has_custom_token = has_custom_token(signer::address_of(creator));
        assert!(has_custom_token, 1);
    }

    // Test getting an CustomToken, when user has not minted
    #[test(aptos = @0x1, account = @custom_token_addr, creator = @0x123)]
    #[expected_failure(abort_code = 524291, location = custom_token_addr::main)]
    fun test_create_custom_token_twice(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires ObjectController {
        setup_test(aptos, account, creator);

        create_custom_token(creator, utf8(b"test"));
        create_custom_token(creator, utf8(b"test"));
    }
}