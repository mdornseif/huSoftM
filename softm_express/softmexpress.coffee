# husoftm is a toolkit for accessing a AS/400 running SoftM Suite.
# 
# node.js proxy for connectiong huSoftM Python clients to the erlang based odbc_bridge.
# 
# This proxy is meant to run on a gateway and receive query descriptions, verify their
# authenticity by checking a HMAC, generating an SQL query and passing this to odbc_bridge
# which in turn queries an AS/400. Answers are passed back on the same way.
# 
# Keep in mind that the HMAC does not protect against replay attacks - although this shouldn't
# be a big issue since all of this functions can be assumed to be idempotent.
# 
# to use you need node.js installed
# 
#     node softmexpress.js s3kri1t odbc_bridge.local.example.com 8000 8082
# 
# branched of connection2.py, Maximillian Dornseif on 2010-11-28.
# Copyright (c) 2010, 2011 HUDORA. All rights reserved.
# all the heavy lifting is done by https://github.com/nodejitsu/node-http-proxy

# Unser Generelles modell ist das eines "rewriting proxies". Wier kriegen die Anfragen in einem
# HTML - Format, authentifizieren diese, schreiben sie um in das Format des Backend Systems und 
# reichen sie weiter.


colors = require('./lib/colors')
crypto = require('crypto')
http = require('http')
httpProxy = require('./lib/node-http-proxy')
querystring = require('querystring')
url = require('url')
util = require('util')

welcome = '''
                __             _         _   _                                          
              /    )         /  `        /  /|                                          
          ----\\--------__--_/__---_/_---/| /-|----__---|/------__---)__----__---__---__-
               \\     /   ) /      /    / |/  |  /___)  |     /   ) /   ) /___) (_ ` (_ `
          _(____/___(___/_/______(_ __/__/___|_(___ __/|____/___/_/_____(___ _(__)_(__)_
                     Midrange over HTTP                    /     /                      
                                                          /                             '''
util.puts(welcome.yellow.bold)

args = process.argv.slice(2)
password = args[0] || 'geheim'
desthost = args[1] || 'localhost'
destport = args[2] || '8000'
listenport = args[3] || '8082'


# Send a Message to the client
sendReply = (response, code, message) ->
    response.writeHead code,
              "Content-Type": 'text/plain',
              "Server": "SoftMexpress/Node.js/" + process.version +  " " + process.platform,
              "Date": (new Date()).toUTCString()
    response.write(message)
    response.write("\n")
    response.end()


# Überprüfe Credentials und wenn die stimmen, rufe `handler` auf.
login_required = (request, response, handler) ->
    # HMAC der URL berechnen
    hmac = crypto.createHmac('sha1', password)
    hmac.update(request.url)
    digest = hmac.digest(encoding='hex')
    # Prüfen, ob der Client den gleichen HMAC mitgeliefert hat
    if request.headers['x-sig'] != digest
        # Nein. Daten loggen und Fehlermeldung zum Client zurück senden
        console.log(request.headers['x-sig'])
        console.log(digest)
        sendReply(response, 401, "Not with me!")
    else
        # User authentifiziert. Handler aufrufen.
        handler(request, response)


# Kodierte SQL Select abfrage ausführen
select = (request, response) ->
    # Die Query als JSON sollte URL-encoded im parameter q in der URL stecken
    # (d.h. queries sind automatisch längenbegrenzt)
    query = JSON.parse(querystring.parse(parsedurl.query).q)
    # Aus den verschiedenen JSON feldern bauen wir nun die eigentliche SQL query zusammen.
    querystr = "SELECT " + query.fields.join(',') + " FROM " + query.tablenames.join(',')
    # Wenn JOIN-Parameter gegeben wurden diese der Query zufügen
    if query.joins
        query.joins.forEach (x) ->
            jointable = x[0]
            leftattr = x[1]
            rightattr = x[2]
            querystr = querystr + ' LEFT OUTER JOIN ' + jointable + ' ON ' + leftattr + '=' + rightattr
    # Verschiedene weitere Parametertypen nach Bedarf zufügen. Wir gehen
    # davon aus, das der Client schonn das Escaping vorgenommen hat
    if query.condition
        querystr = querystr + ' WHERE ' + query.condition.replace(/';/g, "")
    if query.grouping
        querystr = querystr + ' GROUP BY ' + query.grouping.join(',').replace(/';/g, "")
    if query.ordering
        querystr = querystr + ' ORDER BY ' + query.ordering.join(',').replace(/';/g, "")
    # Limit wird auf der AS/400 ... ungewöhnlich implementiert.
    if query.limit
        querystr = querystr + ' FETCH FIRST ' + (query.limit + '').replace(/';/g, "") + ' ROWS ONLY'
    # Alle Queries auf der Console loggen.
    console.log(request.client.remoteAddress + ': ' + querystr);
    # Nun eine neue URL kostruieren und die URL im Request durch diese neue URL ersetzen.
    # Im grunde sind wir hier ein URL rewriter.
    newurl = '/select?' + querystring.stringify({query: querystr, tag: query.tag + '+sEx'})
    request.url = newurl
    # Proxy Objekt für diesen REquest erstellen und ausführen.
    proxy = new httpProxy.HttpProxy(request, response)
    proxy.proxyRequest(destport, desthost)


# Implementierung von Pythons `string.startswith()`
startswith = (s1, s2) ->
    return s1.substr(0, s2.length) == s2


# Mein Server Code
server = httpProxy.createServer (request, response) ->
    parsedurl = url.parse(request.url)
    if parsedurl.pathname == '/info' || request.method != 'GET'
        # Info Requests are just proxied as is.
        request.url = '/info'
        proxy = new httpProxy.HttpProxy(request, response)
        proxy.proxyRequest(destport, desthost)
    else if  parsedurl.pathname == '/stats' || request.method == 'GET'
        # return statuistics information
            sendReply(response, 200, "query_counter: " + query_counter)
    else if startswith(parsedurl.pathname, '/sql')
        if request.method != 'GET'
            sendReply(response, 405, "Method not allowed")
        else
            login_required(request, response, select)
    else
        sendReply(response, 404, "Not here!")


server.listen(listenport)

util.puts('proxy server '.blue + 'started '.green.bold + 'on port '.blue + (listenport + '').yellow)
util.puts(' connecting to '.blue + (desthost + ':' + destport).yellow)