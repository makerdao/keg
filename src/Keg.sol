pragma solidity >=0.5.15;

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

contract LibNote {
    event LogNote(
        bytes4   indexed  sig,
        address  indexed  usr,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes             data
    ) anonymous;

    modifier note {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: selector, caller, arg1 and arg2
            let mark := msize                         // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 caller,                              // msg.sender
                 calldataload(4),                     // arg1
                 calldataload(36)                     // arg2
                )
        }
    }
}

contract VatLike {
	function suck(address, address, uint) external;
    function hope(address) external;
}

contract DaiJoinLike {
    function dai() external view returns (address);
    function join(address, uint) external;
	function exit(address, uint) external;
}

contract DSTokenLike {
    function approve(address) public returns (bool);
    function allowance(address, address) public returns (uint);
    function balanceOf(address) public returns (uint);
    function move(address, address, uint) public;
}

contract Keg is LibNote {

	// --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; emit NewBrewMaster(usr); }
    function deny(address usr) external note auth { wards[usr] = 0; emit RetiredBrewMaster(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "Keg/not-authorized");
        _;
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external note auth { stopped = 1; }
    function start() external note auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Keg/is-stopped"); _; }

    VatLike 	public vat;
    DaiJoinLike public join;
    DSTokenLike public dai;
    address 	public vow;

    uint256 constant RAY = 10 ** 27;

    //accounting for tracking users balances
    mapping (address => uint) public mugs;

    //two-way mapping tracks delegates
    mapping (address => address) public pals;   //delegate -> original
    mapping (address => address) public buds;   //original -> delegate

    // --- Events ---
    event NewBrewMaster(address brewmaster);
    event RetiredBrewMaster(address brewmaster);
    event BrewBeer(uint256 beer);
    event PourBeer(address bartender, uint256 beer);
    event DrinkingBuddy(address indexed owner, address delegate);
    event ByeFelicia(address indexed owner, address delegate);
    event JustASip(address bud, address pal, uint256 beer);
    event DownTheHatch(address bud, address pal, uint256 beer);

    constructor(address vat_, address join_, address vow_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        join = DaiJoinLike(join_);
        dai = DSTokenLike(join.dai());
        vow = vow_;
        vat.hope(address(join));
    }

    //credit compensation to payees
    function brew(address[] calldata bums, uint[] calldata wad) external note auth stoppable {
    	uint256 beer = 0;
        require(bums.length != uint256(0));
    	require(bums.length == wad.length, "Keg/unequal-payees-and-amounts");
    	for (uint i = 0; i < wad.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            mugs[bums[i]] = add(mugs[bums[i]], wad[i]);
            beer = add(beer, wad[i]);
    	}
    	vat.suck(address(vow), address(this), mul(beer, RAY));
        emit BrewBeer(beer);
    }

    function pour(address[] calldata bums, uint[] calldata wad) external note stoppable {
        uint256 beer = 0;
        require(bums.length == wad.length, "Keg/unequal-payees-and-amounts");
        for (uint i = 0; i < wad.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            mugs[bums[i]] = add(mugs[bums[i]], wad[i]);
            beer = add(beer, wad[i]);
        }
        dai.move(msg.sender, address(this), beer);
        if (dai.allowance(address(this), address(join)) != uint(-1)) require(dai.approve(address(join)));
        join.join(address(this), beer);
        emit PourBeer(msg.sender, beer);
    }

    //user delegates compensation to another address
    function pass(address bud) external {
        require(bud != msg.sender, "Keg/cannot_delegate_to_self");
        require(pals[bud] == address(0), "Keg/bud-already-has-a-pal");
        //remove existing delegate
        if (buds[msg.sender] != address(0)) yank();
        //original addr -> delegated addr
        buds[msg.sender] = bud;
        //delegated addr -> original addr
        pals[bud] = msg.sender;
        emit DrinkingBuddy(msg.sender, bud);
    }

    //user revokes delegation
    function yank() public {
        require(buds[msg.sender] != address(0), "Keg/no-bud");
        emit ByeFelicia(msg.sender, buds[msg.sender]);
        pals[buds[msg.sender]] = address(0);
        buds[msg.sender] = address(0);
    }

    //user withdraws all their compensation
    function chug() external {
        address bum;
        uint256 beer;
        //whose tab are we drinking on
        pals[msg.sender] != address(0) ? bum = pals[msg.sender] : bum = msg.sender;
        beer = mugs[bum];
        require(beer != uint256(0), "Keg/too-thirsty-not-enough-beer");
        mugs[bum] = sub(mugs[bum], beer);
        require(mugs[bum] == uint(0));
        join.exit(msg.sender, beer);
        emit DownTheHatch(bum, msg.sender, beer);
    }

    //user withdraws some of their compensation
    function sip(uint256 beer) external {
        address bum;
        //whose tab are we drinking on
        pals[msg.sender] != address(0) ? bum = pals[msg.sender] : bum = msg.sender;
        require(beer <= mugs[msg.sender], "Keg/too-thirsty-not-enough-beer");
        mugs[bum] = sub(mugs[bum], beer);
        require(mugs[bum] >= uint(0));
        join.exit(msg.sender, beer);
        emit JustASip(bum, msg.sender, beer);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
    	if (what == "vat") vat = VatLike(addr);
    	else if (what == "join") join = DaiJoinLike(addr);
        else if (what == "dai") dai = DSTokenLike(addr);
    	else if (what == "vow") vow = addr;
    	else revert("Keg/file-unrecognized-param");
    }
}