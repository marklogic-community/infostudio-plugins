xquery version "1.0-ml";

(: Copyright 2002-2011 Mark Logic Corporation.  All Rights Reserved. :)

declare namespace tweet = "http://marklogic.com/extension/plugin/twitter";

import module namespace plugin = "http://marklogic.com/extension/plugin" at "/MarkLogic/plugin/plugin.xqy";
import module namespace info="http://marklogic.com/appservices/infostudio" at "/MarkLogic/appservices/infostudio/info.xqy";
import module namespace infodev="http://marklogic.com/appservices/infostudio/dev" at "/MarkLogic/appservices/infostudio/infodev.xqy";

declare namespace ml="http://marklogic.com/appservices/mlogic";
declare namespace lbl="http://marklogic.com/xqutils/labels";
declare default function namespace "http://www.w3.org/2005/xpath-functions";

(:~ Map of capabilities implemented by this Plugin. 
:
: Required capabilities for all Collectors
: - http://marklogic.com/appservices/infostudio/collector/model
: - http://marklogic.com/appservices/infostudio/collector/start
: - http://marklogic.com/appservices/string
:)

declare function tweet:capabilities()
as map:map
{
    let $map := map:map()
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/model", xdmp:function(xs:QName("tweet:model")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/start", xdmp:function(xs:QName("tweet:start")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/cancel", xdmp:function(xs:QName("tweet:cancel")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/validate", xdmp:function(xs:QName("tweet:validate")))
    let $_ := map:put($map, "http://marklogic.com/appservices/string", xdmp:function(xs:QName("tweet:string")))
    return $map
};

(:~ Data model underlying UI; represents the data to be passed into invoke :)
declare function tweet:model() 
as element(plugin:plugin-model) 
{
    <plugin:plugin-model>
      <plugin:data/>
    </plugin:plugin-model>
};

(:~ Invoke the plugin :)
declare function tweet:start(
  $model as element(),
  $ticket-id as xs:string,
  $policy-deltas as element(info:options)?
) 
as empty-sequence() 
{
    let $entries := for $a in 1 to 20 
    (: can increase to 149 by default for an hour 
       can increase to more if you contact twitter and they whitelist your ip address:)
                    let $public-timeline:= xdmp:http-get("http://api.twitter.com/1/statuses/public_timeline.xml?include_entities=true")
                    let $response := $public-timeline[1]
                    let $statuses := $public-timeline/statuses/status
                    return $statuses

    let $entry-count := fn:count($entries)

    let $name := fn:data(info:ticket($ticket-id)/info:policy-name)
    let $max :=  fn:data(infodev:effective-policy($name,())/info:max-docs-per-transaction)
    let $max-log := xdmp:log(fn:concat("MAX DOCS PER TRANSACTION",$max)) 
    let $transaction-size := $max
    let $total-transactions := ceiling($entry-count div $transaction-size)

    let $set-total := infodev:ticket-set-total-documents($ticket-id, $entry-count)
    let $set-trans := infodev:ticket-set-total-transactions($ticket-id,$total-transactions)

    let $transactions :=
        for $i at $index in 1 to $total-transactions
        let $map := map:map()
        let $start :=  (($i -1) *$transaction-size) + 1
        let $finish := min((($start  - 1 + $transaction-size),$entry-count))
        let $put :=
            for $entry in ($entries)[$start to $finish]
            let $id := fn:concat("/", fn:format-dateTime(fn:current-dateTime(), "[Y01]-[M01]-[D01]_[H01]-[m01]-[s01]-[f01]") ,"/", $index ,"/",$entry/id/text(),".xml")
            return map:put($map,$id,$entry)
        return $map
    let $function := xdmp:function(xs:QName("tweet:process-file"))
    let $ingestion :=
        for $transaction at $index in $transactions
        return
           try {
               infodev:transaction($transaction,$ticket-id,$function,$policy-deltas,$index,(),())
           } catch($e) {
               infodev:handle-error($ticket-id, concat("transaction ",$index), $e)
           }
    let $_ := infodev:ticket-set-status($ticket-id, "completed") 
    return ()

};

declare function tweet:process-file(
    $document as node()?,
    $source-location as xs:string,
    $ticket-id as xs:string,
    $policy-deltas as element(info:options)?,
    $context as item()?)
as xs:string+
{
        infodev:ingest($document,$source-location,$ticket-id,$policy-deltas)
              
};

(:~ A stand-alone page to configure the collector :)
(: no view here, so no configure button in the UI 
declare function tweet:view($model as element(plugin:plugin-model)?, $lang as xs:string, $submit-here as xs:string)
as element(plugin:config-view)
{
};
:)

declare function tweet:cancel($ticket-id as xs:string) 
as empty-sequence()
{
    infodev:ticket-set-status($ticket-id,"cancelled")
};

(:~ Validate a given model, return () if good, specific errors (with IDs) if problems :)
declare function tweet:validate(
    $model as element(plugin:plugin-model)
) as element(plugin:report)*
{
   () 
};

(:~ All labels needed for display are collected here. :)
declare function tweet:string($key as xs:string, $model as element(plugin:plugin-model)?, $lang as xs:string) 
as xs:string?
{
    let $labels :=
    <lbl:labels xmlns:lbl="http://marklogic.com/xqutils/labels">
        <lbl:label key="name">
            <lbl:value xml:lang="en">Twitter Collector</lbl:value>
        </lbl:label>
        <lbl:label key="description">
            <lbl:value xml:lang="en">Pull Statuses from Twitter's Public Timeline</lbl:value>
        </lbl:label>
    </lbl:labels>
    return $labels/lbl:label[@key eq $key]/lbl:value[@xml:lang eq $lang]/string()
};

(:~ ----------------Main, for registration---------------- :)

plugin:register(tweet:capabilities(),"collector-twitter.xqy")
