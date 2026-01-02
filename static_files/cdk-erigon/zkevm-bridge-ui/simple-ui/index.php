<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta http-equiv="X-UA-Compatible" content="ie=edge">
        <title>Simple Bridge</title>
        <link rel="stylesheet" href="style.css">
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
        <link rel="manifest" href="/site.webmanifest">
    </head>
    <body>
      <pre>
Bridge Testing Interface
                                                        ...
                                                     .........
                                                  ...............
                                              .......................
                                           ..............................
                                       .................. ...................
                                   ...................       ...................
                                   ...............               ...............
                                   ............                     ............
                                   ..........                         ..........
                     ...           ..........                         ..........
                  .........        ..........                         ..........
              .................    ..........                         ..........
           ....................    ..........                         ..........
       ........................    ..........                         ..........
    .................. ........    ..........                         ..........
..................         ....    ..........                         ..........
...............               .    ..........                      .............
...........                        ..........     ..           .................
..........                         ..........     ......   ...................
..........                         ..........     ........................
..........                         ..........     .....................
..........                         ..........     ..................
..........                         ..........       ............
..........                         ..........          .....
..........                         ..........
...........                       ...........
...............                ..............
..................         ..................
   ..................   ..................
       ...............................
          .........................
              ..................
                  ..........
                     ....
                      .
      </pre>
        <p>
          <em>Warning</em>: This is a specialized engineering tool
          intended for test environments. There is a high risk of
          token loss for untrained users. Only proceed if you are
          thoroughly familiar with the risks and have the necessary
          expertise. Proceed with caution &mdash; you have been
          warned.
        </p>
        <!-- button to connect Metamask -->
        <div>
          <label for="l1-rpc-url">L1 RPC URL</label>
          <input type="text" id="l1-rpc-url" name="l1-rpc-url" value="https://eth.rpc.blxrbdn.com">

          <label for="l2-rpc-url">L2 RPC URL</label>
          <input type="text" id="l2-rpc-url" name="l2-rpc-url" value="https://zkevm-rpc.com">

          <label for="bridge-api-url">Bridge API URL</label>
          <input type="text" id="bridge-api-url" name="bridge-api-url" value="https://bridge-api.zkevm-rpc.com">

          <label for="lxly-bridge-addr">LxLy Bridge Address</label>
          <input type="text" id="lxly-bridge-addr" name="lxly-bridge-addr" value="0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe">
          <br />
          <br />
          <button id='connectButton'>Connect to Metamask</button>
        </div>

        <div id="deposit-form" style="display:none;">
          <p>
            To make a deposit, complete the following fields
          </p>
            <label for="orig_net">Origin Rollup ID</label>
            <input type="text" id="orig_net" name="orig_net" value="0">

            <label for="dest_net">Destination Rollup ID</label>
            <input type="text" id="dest_net" name="dest_net" value="1">

            <label for="dest_addr">Destination Address</label>
            <input type="text" id="dest_addr" name="dest_addr">

            <label for="amount">Amount (wei) </label>
            <input type="text" id="amount" name="amount" value="1010">

            <label for="orig_addr">Token Address</label>
            <input type="text" id="orig_addr" name="orig_addr" value="0x0000000000000000000000000000000000000000">

            <label for="metadata">Metadata</label>
            <input type="text" id="metadata" name="metadata" value="0x">

            <label for="is_forced">Is Forced</label>
            <input type="checkbox" id="is_forced" name="is_forced" checked>
            <br />

            <button id="deposit-btn">Deposit</button>
        </div>


        <div id="deposit-stuff" style="display:none;">
          <!-- display the connected account -->
          <div>
            Currently Connected Account:
            <span id='connectedAccount'></span>
          </div>



          <p>
            To claim a deposit, specify an account, refresh the list
            of deposits, and then click the claim button.
          </p>
          <label for="claim-account">Account To Claim</label>
          <input type="text" id="claim-account" name="claim-account">

          <button id="refresh-deposits">Refresh Deposits</button>

          <div id="deposits">
          </div>
        </div>

        <script src="https://cdn.jsdelivr.net/npm/web3@4.8.0/dist/web3.min.js" integrity="sha256-4pxRFL2nZ+ykS9Pj/rQDV/qUzLgQH6247OaL7vimQ9o=" crossorigin="anonymous"></script>
        <script src="index.js"></script>
    </body>
</html>
