-define(DHCP_MAGIC_COOKIE, 16#63825363).

% crash/ignore all others
-type op() :: bootrequest | bootreply.
% crash/ignore all others
-type htype() :: ethernet.
-type mac_address() :: {byte(), byte(), byte(), byte(), byte(), byte()}.
-type dhcp_flag() :: broadcast.
-type dhcp_option() ::
    {Tag :: 0..254, Value :: binary()}
    %% end option
    | {Tag :: 255}.

-record(dhcp_message, {
    % Header
    op :: op(),
    htype :: htype(),
    hlen :: byte(),
    hops :: byte(),
    xid :: 0..16#FFFFFFFF,
    secs :: 0..16#FFFF,
    flags :: [dhcp_flag()],

    % Addresses
    ciaddr :: inet:ip4_address(),
    yiaddr :: inet:ip4_address(),
    siaddr :: inet:ip4_address(),
    giaddr :: inet:ip4_address(),
    chaddr :: mac_address(),

    % Strings
    sname :: binary(),
    file :: binary(),

    % Options
    options :: [dhcp_option()]
}).
-type dhcp_message() :: #dhcp_message{}.
