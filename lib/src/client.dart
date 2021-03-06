part of sockjs_client;

class CloseEvent {
  int code;
  String reason;
  bool wasClean;
  var lastEvent;

  CloseEvent({this.code, this.reason, this.wasClean, this.lastEvent});
}

class MessageEvent {
  var data;
  MessageEvent(this.data);
}

class SockJSEvents extends event.Events {
  get open => this["open"];
  get message => this["message"];
  get close => this["close"];
  get heartbeat => this["heartbeat"];
}

class Client implements event.Emitter<SockJSEvents> {

  SockJSEvents on = new SockJSEvents();

  bool debug;
  bool devel;

  String _baseUrl;
  String server = null;
  String protocol = null;
  List _protocols = [];

  int readyState = CONNECTING;

  Info info;
  num rtt;
  num rto;
  List<String> protocolsWhitelist = [];

  var _ir;

  var _transport = null;
  Timer _transportTref;

  Client(String url, {
    this.devel: false, this.debug: false, this.protocolsWhitelist,
    this.info, this.rtt: 0, this.server}) {

    _baseUrl = utils.amendUrl(url);

    if (server == null) {
      server = utils.random_number_string(1000);
    }

    _ir = new InfoReceiver.forURL(_baseUrl);
    _ir.on.finish.add((InfoReceiverEvent evt) {
        _ir = null;
        if (evt.info != null) {
            _applyInfo(evt.info);
            _didClose();
        } else {
            _didClose(1002, 'Can\'t connect to server', true);
        }
    });
  }

  send(data) {
    if (readyState == CONNECTING) {
        throw 'INVALID_STATE_ERR';
    }
    if (readyState == OPEN) {
        _transport.doSend(utils.quote(data));
    }
    return true;
  }

  _didClose([int code = 0, String reason = "", bool force = false]) {
    if (readyState != CONNECTING &&
        readyState != OPEN &&
        readyState != CLOSING) {
            throw 'INVALID_STATE_ERR';
    }
    if (_ir != null) {
        _ir.nuke();
        _ir = null;
    }

    if (_transport != null) {
        _transport.doCleanup();
        _transport = null;
    }

    var close_event = new CloseEvent(
        code: code,
        reason: reason,
        wasClean: utils.userSetCode(code));

    if (!utils.userSetCode(code) &&
        readyState == CONNECTING && !force) {
        if (_tryNextProtocol(close_event)) {
            return;
        }
        close_event = new CloseEvent( code: 2000,
                                      reason: "All transports failed",
                                      wasClean: false,
                                      lastEvent: close_event );
    }
    readyState = CLOSED;

    utils.delay(() => on.close.dispatch(close_event));
  }

  _dispatchOpen() {
    if (readyState == CONNECTING) {
        if (_transportTref != null) {
            _transportTref.cancel();
            _transportTref = null;
        }
        readyState = OPEN;
        on.open.dispatch();
    } else {
        // The server might have been restarted, and lost track of our
        // connection.
        _didClose(1006, "Server lost session");
    }
  }

  _dispatchMessage(data) {
    if (readyState != OPEN) {
            return;
    }
    on.message.dispatch(new MessageEvent(data));
  }

  _dispatchHeartbeat() {
    if (readyState !== OPEN) {
        return;
    }
    on.heartbeat.dispatch();
  }

  _didMessage(String data) {
    var type = data[0];
    switch(type) {
    case 'o':
        _dispatchOpen();
        break;
    case 'a':
      var s = data.substring(1);
      if (s == null) s = '[]';
      var payload = JSON.parse(s);
      for(var i=0; i < payload.length; i++){
          _dispatchMessage(payload[i]);
      }
      break;
    case 'm':
      var s = data.substring(1);
      if (s == null) s = 'null';
      var payload = JSON.parse(s);
      _dispatchMessage(payload);
      break;
    case 'c':
      var s = data.substring(1);
      if (s == null) s = '[]';
      var payload = JSON.parse(s);
      _didClose(payload[0], payload[1]);
      break;
    case 'h':
      _dispatchHeartbeat();
      break;
    }
  }

  bool _tryNextProtocol([CloseEvent closeEvent]) {
    if (protocol != null) {
        _debug('Closed transport: $protocol $closeEvent');
        protocol = null;
    }
    if (_transportTref != null) {
        _transportTref.cancel();
        _transportTref = null;
    }

    while(true) {

      if (_protocols.isEmpty) {
        return false;
      }

      protocol = _protocols.removeAt(0);

      // Some protocols require access to `body`, what if were in
      // the `head`?
      if (PROTOCOLS.containsKey(protocol) &&
          PROTOCOLS[protocol].needBody &&
          ( (document.body == null) || (document.readyState != null && document.readyState != 'complete'))
          ) {
          _protocols.insertRange(0, 1, protocol);
          this.protocol = 'waiting-for-load';
          document.on.load.add( (_) => _tryNextProtocol());
          return true;
      }

      if (!PROTOCOLS.containsKey(protocol) ||
            !PROTOCOLS[protocol].enabled) {
          _debug('Skipping transport: $protocol');
      } else {
          var roundTrips = PROTOCOLS[protocol].roundTrips;
          var to = rto * roundTrips;
          if (to == 0) to = 5000;
          _transportTref = utils.delay(() {
              if (readyState == CONNECTING) {
                  // I can't understand how it is possible to run
                  // this timer, when the state is CLOSED, but
                  // apparently in IE everythin is possible.
                  _didClose(2007, "Transport timeouted");
              }
          }, to);

          var connid = utils.random_string(8);
          var trans_url = "$_baseUrl/$server/$connid";
          _debug('Opening transport: $protocol url:$trans_url RTO:$rto');
          _transport = PROTOCOLS[protocol].create(this, trans_url, _baseUrl);
          return true;
      }
    }
  }

  _applyInfo(var info) {
    this.info = info;
    this.rto = utils.countRTO(rtt);
    var probed = utils.probeProtocols();
    _protocols = utils.detectProtocols(probed, protocolsWhitelist, info);
  }

  _debug(String msg) {
    if (debug) {
       print(msg);
    }
  }

}
