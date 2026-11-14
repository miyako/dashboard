property collector : cs._DashboardCollector
property state; event; monitor : Object
property callbackEnabled : Boolean
property notifying; terminal : Boolean
property notifications : Collection

Class constructor($state : Object; $event : Object; $monitor : Object)
	This.state:=$state
	This.event:=$event
	This.monitor:=$monitor
	This.callbackEnabled:=(Value type($event.onStatus)=Is object)
	This.notifying:=False
	This.terminal:=False
	This.notifications:=New collection

Function sample($signal : 4D.Signal)
	var $payload : Object
	If (This.collector=Null)
		This.collector:=cs._DashboardCollector.new()
	End if
	$payload:=New object("info"; This.collector.info; "snapshot"; This.collector.snapshot())
	Use ($signal)
		$signal.payload:=JSON Stringify($payload)
	End use
	$signal.trigger()

Function notify($kind : Text; $status : Object)
	This.notifications.push(New object("kind"; $kind; "status"; $status))
	If (This.notifying)
		return
	End if
	This.notifying:=True
	var $notification : Object
	While (This.notifications.length>0)
		$notification:=This.notifications.shift()
		This._notify($notification.kind; $notification.status)
	End while
	This.notifying:=False

Function _notify($kind : Text; $status : Object)
	var $errors : Collection
	If (($kind="stopped") | ($kind="failed"))
		This.terminal:=True
	End if
	If ($status=Null)
		$status:=New object("kind"; $kind; "status"; This.state.status; "url"; This.state.url; "error"; This.state.error; "samples"; This.state.samples; "epoch"; This.state.epoch; "port"; This.state.port; "finished"; This.state.finished)
	End if
	If ($kind="running")
		$status.portCheck:=Try(This.portStatus($status.port))
		If (Last errors#Null)
			$status.portCheck:=New object("availability"; "error"; "reason"; JSON Stringify(Last errors))
		End if
	End if
	If (This.callbackEnabled)
		Try(This.event.onStatus.call(This.event; $status; This.monitor))
		$errors:=Last errors
		If ($errors#Null)
			Use (This.state)
				This.state.callbackError:=JSON Stringify($errors)
				If (This.state.error="")
					This.state.error:="Dashboard status callback failed"
				End if
				This.state.status:="failed"
				This.state.url:=""
			End use
			This.callbackEnabled:=False
			This.monitor.stop()
		End if
	End if

Function portStatus($port : Integer)->$result : Object
	var $tcp : cs.tcp.tcp
	var $option : Object
	var $responses; $owners : Collection
	$tcp:=cs.tcp.tcp.new()
	$tcp.controller.timeout:=3
	$option:=New object("port"; $port)
	$responses:=$tcp.check($option)
	If (Value type($option.error)=Is text)
		return New object("availability"; "error"; "reason"; $option.error)
	End if
	If ($responses=Null)
		return New object("availability"; "error"; "reason"; "TCP query returned no result")
	End if
	If ($responses.length#1)
		return New object("availability"; "error"; "reason"; "TCP query returned an invalid result count")
	End if
	If (Value type($responses[0])#Is text)
		return New object("availability"; "error"; "reason"; "TCP query returned no JSON")
	End if
	$owners:=$tcp.get($port; JSON Parse($responses[0]; Is collection))
	$result:=New object("availability"; "available"; "listening"; ($owners#Null))
