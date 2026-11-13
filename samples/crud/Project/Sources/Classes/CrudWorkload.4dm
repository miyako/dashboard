property phase : Integer
property batchNumber : Integer
property counts : Object
property error : Text
property keys : Collection
property createdPayload : Text
property updatedPayload : Text

Class constructor
	var $i : Integer
	This.phase:=0
	This.batchNumber:=0
	This.error:=""
	This.counts:=New object("create"; 0; "read"; 0; "update"; 0; "delete"; 0; "cycles"; 0)
	This.keys:=New collection
	This.createdPayload:="C"
	This.updatedPayload:="U"
	For ($i; 1; 13)
		This.createdPayload+=This.createdPayload
		This.updatedPayload+=This.updatedPayload
	End for
	If (ds.CrudRecords.all().length#0)
		This.error:="Sample requires a new, empty data file"
	End if

Function step()->$phase : Text
	var $i : Integer
	var $entity : 4D.Entity
	var $selection : 4D.EntitySelection
	var $saved : Object
	$phase:="failed"
	If (This.error#"")
		return
	End if
	Case of
		: (This.phase=0)
			$phase:="create"
			This.batchNumber+=1
			This.keys:=New collection
			For ($i; 1; 128)
				$entity:=ds.CrudRecords.new()
				$entity.batchNumber:=This.batchNumber
				$entity.ordinal:=$i
				$entity.revisionNumber:=0
				$entity.payloadText:=This.createdPayload
				$saved:=$entity.save()
				If (Not($saved.success))
					This.error:="Create failed: "+JSON Stringify($saved)
					return
				End if
				This.keys.push($entity.getKey())
				This.counts.create+=1
			End for
			FLUSH CACHE
			If (ds.CrudRecords.all().length#128)
				This.error:="Create count mismatch"
				return
			End if
		: (This.phase=1)
			$phase:="read"
			// This isolated test deliberately evicts cache to exercise real disk reads.
			FLUSH CACHE(*)
			$selection:=ds.CrudRecords.query("batchNumber = :1 order by ordinal"; This.batchNumber)
			If ($selection.length#128)
				This.error:="Indexed query count mismatch"
				return
			End if
			For ($i; 0; 127)
				$entity:=$selection[$i]
				If (($entity.ordinal#($i+1)) | ($entity.revisionNumber#0) | ($entity.payloadText#This.createdPayload))
					This.error:="Created record round-trip mismatch"
					return
				End if
				This.counts.read+=1
			End for
		: (This.phase=2)
			$phase:="update"
			For ($i; 0; 127)
				$entity:=ds.CrudRecords.get(This.keys[$i])
				If ($entity=Null)
					This.error:="Record missing before update"
					return
				End if
				$entity.revisionNumber:=1
				$entity.payloadText:=This.updatedPayload
				$saved:=$entity.save()
				If (Not($saved.success))
					This.error:="Update failed: "+JSON Stringify($saved)
					return
				End if
				This.counts.update+=1
			End for
			FLUSH CACHE
		: (This.phase=3)
			$phase:="delete"
			FLUSH CACHE(*)
			For ($i; 0; 127)
				$entity:=ds.CrudRecords.get(This.keys[$i])
				If ($entity=Null)
					This.error:="Record missing before delete"
					return
				End if
				If (($entity.revisionNumber#1) | ($entity.payloadText#This.updatedPayload))
					This.error:="Updated record round-trip mismatch"
					return
				End if
				$saved:=$entity.drop()
				If (Not($saved.success))
					This.error:="Delete failed: "+JSON Stringify($saved)
					return
				End if
				This.counts.delete+=1
				If (ds.CrudRecords.get(This.keys[$i])#Null)
					This.error:="Deleted primary key still exists"
					return
				End if
			End for
			FLUSH CACHE
			If (ds.CrudRecords.all().length#0)
				This.error:="Deleted records remain"
				return
			End if
			This.counts.cycles+=1
		Else
			$phase:="idle"
	End case
	This.phase:=Mod(This.phase+1; 8)

Function finish()
	While ((This.phase>0) & (This.phase<4) & (This.error=""))
		This.step()
	End while
