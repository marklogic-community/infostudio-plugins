xquery version "1.0-ml";

(: Copyright 2002-2011 Mark Logic Corporation.  All Rights Reserved. :)

declare namespace csvscan = "http://marklogic.com/extension/plugin/csvscan";

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

declare function csvscan:capabilities()
as map:map
{
    let $map := map:map()
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/model", xdmp:function(xs:QName("csvscan:model")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/start", xdmp:function(xs:QName("csvscan:start")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/config-view", xdmp:function(xs:QName("csvscan:view")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/cancel", xdmp:function(xs:QName("csvscan:cancel")))
    let $_ := map:put($map, "http://marklogic.com/appservices/infostudio/collector/validate", xdmp:function(xs:QName("csvscan:validate")))
    let $_ := map:put($map, "http://marklogic.com/appservices/string", xdmp:function(xs:QName("csvscan:string")))
    return $map
};

(:~ Data model underlying UI; represents the data to be passed into invoke :)
declare function csvscan:model() 
as element(plugin:plugin-model) 
{
    <plugin:plugin-model>
      <plugin:data>
        <dir>Enter directory here</dir>
        <delimiter>,</delimiter>
        <headers>true</headers>
		<splitbyrow>true</splitbyrow>
      </plugin:data>
    </plugin:plugin-model>
};

(:~ Invoke the plugin :)
declare function csvscan:start(
  $model as element(),
  $ticket-id as xs:string,
  $policy-deltas as element(info:options)?
) 
as empty-sequence() 
{
    let $dir := $model/plugin:data/dir/string()
    let $function := xdmp:function(xs:QName("csvscan:process-file"))
    return infodev:filesystem-walk($dir,$ticket-id,$function,$policy-deltas,$model)
};

declare function csvscan:process-file(
    $document as node()?,
    $source-location as xs:string,
    $ticket-id as xs:string,
    $policy-deltas as element(info:options)?,
    $context as item()?)
as xs:string*
{
    let $document := infodev:get-file($source-location,$ticket-id,$policy-deltas)
    let $mimetype := xdmp:uri-content-type($source-location)

    let $use-headers := if($context/plugin:data/headers/string() eq "true") then
                             fn:true()
                        else
                             fn:false()

    let $delimiter := $context/plugin:data/delimiter/string()

	let $splitbyrow := if($context/plugin:data/splitbyrow/string() eq "true") then
                             fn:true()
                        else
                             fn:false()
							 
    let $result := 
        if(fn:ends-with($mimetype,"/csv"))
        then
          try {
               let $csv-name := fn:concat(fn:substring-before($source-location,".csv"),".xml")
               let $lines :=  fn:tokenize($document,"[\n\r]+") 
               let $line := $lines[1]
               let $header-elements := if($use-headers) then 
                                         let $headers := fn:tokenize($line, $delimiter)
                                         let $header-elems := for $h in $headers
                                                              let $upd := fn:replace($h," ","_") 
                                                              return if(fn:matches($upd,"^([a-zA-Z]+[_0-9-]*)+[a-zA-Z0-9]+$")) then
                                                                         element{fn:QName((),$upd)} {$upd}
                                                                     else
                                                                         fn:error(xs:QName("ERROR"), "Value Cannot Be Used As Element Name. Please Reconfigure to Use Defaults.") 
                                         return $header-elems
                                       else
                                         ()

               let $csv:=  <csv>{
                                if(fn:empty($header-elements)) then
                                    for $line in $lines[1 to fn:count($lines)-1]
									let $line := csvscan:remove-quoted-commas($line)
                                    return <row>{
                                                 let $l := fn:tokenize($line,$delimiter)
                                                 return for $ln at $idx in $l
													   let $ln := csvscan:put-back-quoted-commas($ln)
                                                       return element {fn:concat("column",$idx)} {$ln}
                                          }</row>
                                else
                                    for $l in $lines[2 to fn:count($lines)-1]
 									let $l := csvscan:remove-quoted-commas($l)
                                    let $line-vals := fn:tokenize($l, $delimiter)
                                    return <row>{
                                                 for $lv at $d in $line-vals
												 let $lv := csvscan:put-back-quoted-commas($lv)
                                                 return element {fn:name($header-elements[$d])} {$lv}
                                          }</row>
                          }</csv>
               
               return if ($splitbyrow) then
						for $row at $d in $csv/row
						let $row-name := fn:concat($csv-name, $d)
						return infodev:ingest($row, $row-name, $ticket-id, $policy-deltas)
					  else
						infodev:ingest($csv, $csv-name, $ticket-id, $policy-deltas)

          } catch($e) {
                (infodev:handle-error($ticket-id, $source-location, $e), xdmp:log(fn:concat("ERROR",$e)))
          }
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
declare function csvscan:view($model as element(plugin:plugin-model)?, $lang as xs:string, $submit-here as xs:string)
as element(plugin:config-view)
{
    let $sel := attribute selected { "selected" }
    let $delimiter := $model/plugin:data/delimiter
    let $headers := $model/plugin:data/headers
	let $splitbyrow := $model/plugin:data/splitbyrow

    let $delimiter-options :=
                  <options>
                    <option value=",">,</option>
                    <option value="\|">|</option>
                   </options>

    let $header-options :=
                  <options>
                    <option value="true">true</option>
                    <option value="false">false</option>
                   </options>

    let $split-options :=
                  <options>
                    <option value="true">true</option>
                    <option value="false">false</option>
                   </options>

				   return
     <config-view xmlns="http://marklogic.com/extension/plugin">
        <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
                <title>iframe plugin configuration</title>
            </head>
            <body>
              <h2>Directory CSV Loader Configuration</h2>
              <form style="margin-top: 20px;" action="{$submit-here}" method="post">
                  <label for="dir">{ csvscan:string("dir-label", $model, $lang) }</label>
                  <input type="text" name="dir" id="dir" style="width: 400px" value="{$model/plugin:data/*:dir}"/>
                  <p style="color: rgb(125,125,125); font-style: italic;">
                    The full path on the remote host. This directory and its contents must be readable by MarkLogic.
                  </p><br/>
                  <label for="delimiter">{ csvscan:string("delim-label", $model, $lang) }</label>
                   <select name="delimiter" id="delimiter">
                      { for $d in $delimiter-options/* return <option value="{$d/@value}">{if ($d/@value eq $delimiter) then $sel else () }{$d/string()}</option> }
                   </select>
                  <p style="color: rgb(125,125,125); font-style: italic;">
                    Choose the delimiter for your .csv files. 
                  </p>
                  <label for="headers">{ csvscan:string("header-label", $model, $lang) }</label>
                   <select name="headers" id="headers">
                      { for $d in $header-options/* return <option value="{$d/@value}">{if ($d/@value eq $headers) then $sel else () }{$d/string()}</option> }
                   </select>
                  <p style="color: rgb(125,125,125); font-style: italic;">
                    Choose True to use the first row of the .csv as element values. 
                  </p>
                  <label for="splitbyrow">{ csvscan:string("split-label", $model, $lang) }</label>
                   <select name="splitbyrow" id="splitbyrow">
                      { for $d in $split-options/* return <option value="{$d/@value}">{if ($d/@value eq $splitbyrow) then $sel else () }{$d/string()}</option> }
                   </select>
                  <p style="color: rgb(125,125,125); font-style: italic;">
                    Choose True to insert a document by row (False for a document per csv file). 
                  </p>

                  <div style="position: absolute; bottom: 2px; right: 0px;">
                      <ml:submit label="Done"/>
                  </div>
              </form>
            </body>
        </html>
     </config-view>
};

declare function csvscan:cancel($ticket-id as xs:string) 
as empty-sequence()
{
    infodev:ticket-set-status($ticket-id,"cancelled")
};

(:~ Validate a given model, return () if good, specific errors (with IDs) if problems :)
declare function csvscan:validate(
    $model as element(plugin:plugin-model)
) as element(plugin:report)*
{
    if (string-length($model/plugin:data/dir) eq 0)
    then <plugin:report id="dir">Specified directory must not be empty</plugin:report>
    else ()
};

(:~ All labels needed for display are collected here. :)
declare function csvscan:string($key as xs:string, $model as element(plugin:plugin-model)?, $lang as xs:string) 
as xs:string?
{
    let $labels :=
    <lbl:labels xmlns:lbl="http://marklogic.com/xqutils/labels">
        <lbl:label key="name">
            <lbl:value xml:lang="en">Filesystem CSV Directory</lbl:value>
        </lbl:label>
        <lbl:label key="description">
             <lbl:value xml:lang="en">{
                if($model)
                then concat("Load the contents of csv files from this directory on the server: ", 
                              $model/plugin:data/dir/string(), "&lt;br/&gt;",
                            "Using delimiter: ",$model/plugin:data/delimiter/string(),"&lt;br/&gt;",
                            "Use first row of .csv as element names: ",$model/plugin:data/headers/string(),"&lt;br/&gt;",
							"Create a document per row: ",$model/plugin:data/splitbyrow/string()
                           )
                else "Load the contents of csv files from a directory on the server"
             }</lbl:value>
        </lbl:label>
        <lbl:label key="start-label">
            <lbl:value xml:lang="en">Run</lbl:value>
        </lbl:label>
        <lbl:label key="dir-label">
            <lbl:value xml:lang="en">Directory path</lbl:value>
        </lbl:label>
        <lbl:label key="delim-label">
            <lbl:value xml:lang="en">Delimiter</lbl:value>
        </lbl:label>
        <lbl:label key="header-label">
            <lbl:value xml:lang="en">Use First Row as Column Names</lbl:value>
        </lbl:label>
        <lbl:label key="split-label">
            <lbl:value xml:lang="en">Create a Document per Row</lbl:value>
        </lbl:label>
    </lbl:labels>
    return $labels/lbl:label[@key eq $key]/lbl:value[@xml:lang eq $lang]/string()

};

declare function csvscan:remove-quoted-commas($row as xs:string) as xs:string
{
	if (fn:matches($row, "(.*)("")([^""]+),([^""]+)("")(.*)"))
	then csvscan:remove-quoted-commas(fn:replace($row, "(.*)("")([^""]+),([^""]+)("")(.*)","$1$2$3||$4$5$6"))
	else $row
};

declare function csvscan:put-back-quoted-commas($value as xs:string) as xs:string
{
	fn:replace($value, "\|\|",",")
};

(:~ ----------------Main, for registration---------------- :)

plugin:register(csvscan:capabilities(),"collector-csv.xqy")
