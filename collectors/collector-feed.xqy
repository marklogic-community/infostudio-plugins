xquery version "1.0-ml";

(: Copyright 2002-2011 Mark Logic Corporation.  All Rights Reserved. :)

declare namespace feed = "http://marklogic.com/extension/plugin/feed";

import module namespace plugin = "http://marklogic.com/extension/plugin" at "/MarkLogic/plugin/plugin.xqy";
import module namespace info="http://marklogic.com/appservices/infostudio" at "/MarkLogic/appservices/infostudio/info.xqy";
import module namespace infodev="http://marklogic.com/appservices/infostudio/dev" at "/MarkLogic/appservices/infostudio/infodev.xqy";

declare namespace ml="http://marklogic.com/appservices/mlogic";
declare namespace lbl="http://marklogic.com/xqutils/labels";

declare namespace html = "http://www.w3.org/1999/xhtml";
declare namespace atom = "http://www.w3.org/2005/Atom";

declare default function namespace "http://www.w3.org/2005/xpath-functions";

(:~ Map of capabilities implemented by this Plugin.
:
: Required capabilities for all Collectors
: - http://marklogic.com/appservices/infostudio/collector/model
: - http://marklogic.com/appservices/infostudio/collector/start
: - http://marklogic.com/appservices/string
:)

declare function feed:capabilities()
as map:map
{
    let $map := map:map()
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/model", xdmp:function(xs:QName("feed:model")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/start", xdmp:function(xs:QName("feed:start")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/config-view", xdmp:function(xs:QName("feed:view")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/cancel", xdmp:function(xs:QName("feed:cancel")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/validate", xdmp:function(xs:QName("feed:validate")))
    let $_ := map:put($map, "http://marklogic.com/appservices/string", xdmp:function(xs:QName("feed:string")))
    return $map
};

(:~ Data model underlying UI; represents the data to be passed into invoke :)
declare function feed:model()
as element(plugin:plugin-model)
{
    <plugin:plugin-model>
      <plugin:data>
        <uri>Enter URI here</uri>
        <sincedate>Enter Since Date here.  MM/DD/YYYY</sincedate>
      </plugin:data>
    </plugin:plugin-model>
};

(:~ Invoke the plugin :)
declare function feed:start(
  $model as element(),
  $ticket-id as xs:string,
  $policy-deltas as element(info:options)?
)
as empty-sequence()
{
    let $uri := $model/plugin:data/uri/string()
    let $since-date := $model/plugin:data/sincedate/string()

    let $date-tokens := fn:tokenize(fn:normalize-space($since-date),"/")
    let $new-date := if(fn:count($date-tokens) eq 3 ) then xs:dateTime(xs:date(fn:concat($date-tokens[3],"-",$date-tokens[1],"-",$date-tokens[2]))) else ()

    let $xml:= xdmp:http-get($uri)
    let $response := $xml[1]
    let $feed := $xml[2]/atom:feed
    let $entries := if(fn:empty($new-date)) then
                      $feed/atom:entry
                    else
                      $feed/atom:entry[atom:published gt $new-date]

    let $entry-count := fn:count($entries)

    (: get transaction-size from policy :)
    let $name := fn:data(info:ticket($ticket-id)/info:policy-name)
    let $max :=  fn:data(infodev:effective-policy($name,())/info:max-docs-per-transaction)

    let $transaction-size := $max 
    let $total-transactions := ceiling($entry-count div $transaction-size)

    (: set total documents and total transactions so UI displays collecting :)
    let $set-total := infodev:ticket-set-total-documents($ticket-id, $entry-count)
    let $set-trans := infodev:ticket-set-total-transactions($ticket-id,$total-transactions)
 
    (: create transactions by breaking document set into maps
       each maps's documents are saved to the db in their own transaction :)
    let $transactions :=
        for $i at $index in 1 to $total-transactions
        let $map := map:map()
        let $start :=  (($i -1) *$transaction-size) + 1
        let $finish := min((($start  - 1 + $transaction-size),$entry-count))
        let $put :=
            for $entry in ($entries)[$start to $finish]
            let $id := fn:concat(fn:string($entry/atom:id),".xml")
            return map:put($map,$id,$entry)
        return $map

    (: the callback function for ingest :)
    let $function := xdmp:function(xs:QName("feed:process-file"))
    let $ingestion :=
        for $transaction at $index in $transactions
        return
           try {
               infodev:transaction($transaction,$ticket-id,$function,$policy-deltas,$index,(),())
           } catch($e) {
               infodev:handle-error($ticket-id, concat("transaction ",$index), $e)
           }
    (:set ticket completed for UI:)
    let $_ := infodev:ticket-set-status($ticket-id, "completed") 
    return ()
};

declare function feed:process-file(
    $document as node()?,
    $source-location as xs:string,
    $ticket-id as xs:string,
    $policy-deltas as element(info:options)?,
    $context as item()?
)
{
    infodev:ingest($document,$source-location,$ticket-id,$policy-deltas,())
};

(:~ A stand-alone page to configure the collector :)
declare function feed:view($model as element(plugin:plugin-model)?, $lang as xs:string, $submit-here as xs:string)
as element(plugin:config-view)
{
    <config-view xmlns="http://marklogic.com/extension/plugin">
        <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
                <title>iframe plugin configuration</title>
            </head>
            <body>
              <h2>Feed Loader Configuration</h2>
              <form style="margin-top: 20px;" action="{$submit-here}" method="post">
                  <label for="uri">{ feed:string("uri-label", $model, $lang) }</label>
                  <input type="text" name="uri" id="uri" style="width: 400px" value="{$model/plugin:data/*:uri}"/>
                  <p style="color: rgb(125,125,125); font-style: italic;">
                    The feed URI. This feed is assumed to be well-formed ATOM and its contents must be readable by MarkLogic.
                  </p>
                  <label for="sincedate">{ feed:string("sd-label", $model, $lang) }</label>
                  <input type="text" name="sincedate" id="sincedate" style="width: 400px" value="{$model/plugin:data/*:sincedate}"/>
                  <p style="color: rgb(125,125,125); font-style: italic;">
                    Since date.  Load all feeds since date specified.  If not date specified, all will be loaded.  Date must be of format MM/DD/YYYY.
                  </p>
                  <div style="position: absolute; bottom: 2px; right: 0px;">
                      <ml:submit label="Done"/>
                  </div>
              </form>
            </body>
        </html>
    </config-view>
};

declare function feed:cancel($ticket-id as xs:string)
as empty-sequence()
{
    infodev:ticket-set-status($ticket-id,"cancelled")
};

(:~ Validate a given model, return () if good, specific errors (with IDs) if problems :)
declare function feed:validate(
    $model as element(plugin:plugin-model)
) as element(plugin:report)*
{
  
    if (string-length($model/plugin:data/uri) eq 0 )
    then <plugin:report id="uri">Specified feed URI must not be empty</plugin:report>
    else
        let $since-date := $model/plugin:data/sincedate/string()
        let $date-tokens := fn:tokenize(fn:normalize-space($since-date),"/")
        return if((fn:count($date-tokens) eq 3) or  fn:empty($date-tokens)) then
                 ()
               else
                 <plugin:report id="sincedate">Specified date is not the appropriate format (MM/DD/YYYY).</plugin:report>
};

(:~ All labels needed for display are collected here. :)
declare function feed:string($key as xs:string, $model as element(plugin:plugin-model)?, $lang as xs:string)
as xs:string?
{
    let $labels :=
    <lbl:labels xmlns:lbl="http://marklogic.com/xqutils/labels">
        <lbl:label key="name">
            <lbl:value xml:lang="en">Feed Collector</lbl:value>
        </lbl:label>
        <lbl:label key="description">
             <lbl:value xml:lang="en">{
                if($model)
                then concat("Load from this feed: ", $model/plugin:data/uri/string())
                else "Load files from an atom feed"
             }</lbl:value>
        </lbl:label>
        <lbl:label key="start-label">
            <lbl:value xml:lang="en">Run</lbl:value>
        </lbl:label>
        <lbl:label key="dir-label">
            <lbl:value xml:lang="en">Feed URI</lbl:value>
        </lbl:label>
    </lbl:labels>
    return $labels/lbl:label[@key eq $key]/lbl:value[@xml:lang eq $lang]/string()

};

(:~ ----------------Main, for registration---------------- :)

plugin:register(feed:capabilities(),"collector-feed.xqy")
