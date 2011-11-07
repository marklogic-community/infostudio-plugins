xquery version "1.0-ml";

(: Copyright 2002-2011 Mark Logic Corporation.  All Rights Reserved. :)

declare namespace zipscan = "http://marklogic.com/extension/plugin/zipscan";

import module namespace plugin = "http://marklogic.com/extension/plugin" at "/MarkLogic/plugin/plugin.xqy";
import module namespace info="http://marklogic.com/appservices/infostudio" at "/MarkLogic/appservices/infostudio/info.xqy";
import module namespace infodev="http://marklogic.com/appservices/infostudio/dev" at "/MarkLogic/appservices/infostudio/infodev.xqy";

declare namespace ml="http://marklogic.com/appservices/mlogic";
declare namespace lbl="http://marklogic.com/xqutils/labels";

declare namespace zip="xdmp:zip";

declare default function namespace "http://www.w3.org/2005/xpath-functions";

(:~ Map of capabilities implemented by this Plugin. 
:
: Required capabilities for all Collectors
: - http://marklogic.com/appservices/infostudio/collector/model
: - http://marklogic.com/appservices/infostudio/collector/start
: - http://marklogic.com/appservices/string
:)

declare function zipscan:capabilities()
as map:map
{
    let $map := map:map()
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/model", xdmp:function(xs:QName("zipscan:model")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/start", xdmp:function(xs:QName("zipscan:start")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/config-view", xdmp:function(xs:QName("zipscan:view")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/cancel", xdmp:function(xs:QName("zipscan:cancel")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/validate", xdmp:function(xs:QName("zipscan:validate")))
    let $_ := map:put($map, "http://marklogic.com/appservices/string", xdmp:function(xs:QName("zipscan:string")))
    return $map
};

(:~ Data model underlying UI; represents the data to be passed into invoke :)
declare function zipscan:model() 
as element(plugin:plugin-model) 
{
    <plugin:plugin-model>
      <plugin:data>
        <dir>Enter directory here</dir>
      </plugin:data>
    </plugin:plugin-model>
};

(:~ Invoke the plugin :)
declare function zipscan:start(
  $model as element(),
  $ticket-id as xs:string,
  $policy-deltas as element(info:options)?
) 
as empty-sequence() 
{
    let $dir := $model/plugin:data/dir/string()
    let $function := xdmp:function(xs:QName("zipscan:process-file"))
    return infodev:filesystem-walk($dir,$ticket-id,$function,$policy-deltas,())
};

declare function zipscan:process-file(
    $document as node()?,
    $source-location as xs:string,
    $ticket-id as xs:string,
    $policy-deltas as element(info:options)?,
    $context as item()?)
as xs:string*
{
    let $document := infodev:get-file($source-location,$ticket-id,$policy-deltas)
    let $mimetype := xdmp:uri-content-type($source-location)
    let $log-mimetype :=xdmp:log(fn:concat("MIMETYPE:",$mimetype))

    let $result := 
        if(fn:ends-with($mimetype,"/zip"))
        then
          let $manifest := xdmp:zip-manifest($document)

          let $zip-count := fn:count($manifest/zip:part)
          let $current-total := if(fn:empty(xs:integer(info:ticket($ticket-id)/info:total-documents))) then
                                   0
                                else 
                                   xs:integer(info:ticket($ticket-id)/info:total-documents)

          let $total-count := $zip-count + $current-total - 1

          let $log-count := xdmp:log(fn:concat($ticket-id,"COUNT:",$zip-count,"|",$current-total,"|",$total-count))
    
          let $set-total := infodev:ticket-set-total-documents($ticket-id, $total-count)  
 
          let $parts :=
              for $part-name in $manifest/zip:part
              let $options :=  <options xmlns="xdmp:zip-get"/>
              let $part := xdmp:zip-get($document, $part-name, $options)
              return
              try {
                     infodev:ingest($part,$part-name,$ticket-id,$policy-deltas)
              } catch($e) {
                     infodev:handle-error($ticket-id, $part-name, $e)
              }

          return $parts
        else
          let $current-total := if(fn:empty(xs:integer(info:ticket($ticket-id)/info:total-documents))) then
                                   0
                                else 
                                   xs:integer(info:ticket($ticket-id)/info:total-documents)

          let $total-count := $current-total - 1
          let $set-total := infodev:ticket-set-total-documents($ticket-id, $total-count)  
          return  ()  
     return $result

};

(:~ A stand-alone page to configure the collector :)
declare function zipscan:view($model as element(plugin:plugin-model)?, $lang as xs:string, $submit-here as xs:string)
as element(plugin:config-view)
{
    <config-view xmlns="http://marklogic.com/extension/plugin">
        <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
                <title>iframe plugin configuration</title>
            </head>
            <body>
              <h2>Directory Zip Loader Configuration</h2>
              <form style="margin-top: 20px;" action="{$submit-here}" method="post">
                  <label for="dir">{ zipscan:string("dir-label", $model, $lang) }</label>
                  <input type="text" name="dir" id="dir" style="width: 400px" value="{$model/plugin:data/*:dir}"/>
                  <p style="color: rgb(125,125,125); font-style: italic;">
                    The full path on the remote host. This directory and its contents must be readable by MarkLogic.
                  </p>
                  <div style="position: absolute; bottom: 2px; right: 0px;">
                      <ml:submit label="Done"/>
                  </div>
              </form>
            </body>
        </html>
    </config-view>
};

declare function zipscan:cancel($ticket-id as xs:string) 
as empty-sequence()
{
    infodev:ticket-set-status($ticket-id,"cancelled")
};

(:~ Validate a given model, return () if good, specific errors (with IDs) if problems :)
declare function zipscan:validate(
    $model as element(plugin:plugin-model)
) as element(plugin:report)*
{
    if (string-length($model/plugin:data/dir) eq 0)
    then <plugin:report id="dir">Specified directory must not be empty</plugin:report>
    else ()
};

(:~ All labels needed for display are collected here. :)
declare function zipscan:string($key as xs:string, $model as element(plugin:plugin-model)?, $lang as xs:string) 
as xs:string?
{
    let $labels :=
    <lbl:labels xmlns:lbl="http://marklogic.com/xqutils/labels">
        <lbl:label key="name">
            <lbl:value xml:lang="en">Filesystem Zip Directory</lbl:value>
        </lbl:label>
        <lbl:label key="description">
             <lbl:value xml:lang="en">{
                if($model)
                then concat("Load the contents of zip files from this directory on the server: ", $model/plugin:data/dir/string())
                else "Load the contents of zip files from a directory on the server"
             }</lbl:value>
        </lbl:label>
        <lbl:label key="start-label">
            <lbl:value xml:lang="en">Run</lbl:value>
        </lbl:label>
        <lbl:label key="dir-label">
            <lbl:value xml:lang="en">Directory path</lbl:value>
        </lbl:label>
    </lbl:labels>
    return $labels/lbl:label[@key eq $key]/lbl:value[@xml:lang eq $lang]/string()

};


(:~ ----------------Main, for registration---------------- :)

plugin:register(zipscan:capabilities(),"collector-zip.xqy")
