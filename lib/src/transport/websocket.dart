part of sockjs_client;

class WebSocketTransport {
  Client ri;
  var url;

  WebSocket ws;

  static create(ri, transUrl, [baseUrl]) => new WebSocketTransport(ri, transUrl);

  WebSocketTransport(this.ri, transUrl) {
    var url = '$transUrl/websocket';
    if (url.startsWith('https')) {
        url = 'wss${url.substring(5)}';
    } else {
        url = 'ws${url.substring(4)}';
    }

    this.url = url;

    ws = new WebSocket(url);


    ws.on.message.add(_msgHandler);

    // Firefox has an interesting bug. If a websocket connection is
    // created after onbeforeunload, it stays alive even when user
    // navigates away from the page. In such situation let's lie -
    // let's not open the ws connection at all. See:
    // https://github.com/sockjs/sockjs-client/issues/28
    // https://bugzilla.mozilla.org/show_bug.cgi?id=696085
    //that.unload_ref = utils.unload_add(function(){that.ws.close()});
    ws.on.close.add(_closeHandler);
  }

  _msgHandler(m) => ri._didMessage(m.data);

  _closeHandler(m) => ri._didMessage(utils.closeFrame(1006, "WebSocket connection broken"));

  doSend(data) => ws.send('[$data]');

  doCleanup() {
    if (ws != null) {
        ws.on.message.remove(_msgHandler);
        ws.on.close.remove(_closeHandler);
        ws.close();
        //utils.unload_del(that.unload_ref);
        //that.unload_ref = null;
        ri = ws = null;
    }
  }

  static bool get enabled {
    var res = true;
    var ws;

    // Ugly detection stuff - must be online
    try {
      ws = new WebSocket('ws://echo.websocket.org');
    } on dynamic catch(e) {
      res = false;
    } finally {
      try {
        ws.on.open.add((e) => ws.close());
      } catch (_){}
    }

    return res;
  }


// In theory, ws should require 1 round trip. But in chrome, this is
// not very stable over SSL. Most likely a ws connection requires a
// separate SSL connection, in which case 2 round trips are an
// absolute minumum.
  static const roundTrips = 2;
}
