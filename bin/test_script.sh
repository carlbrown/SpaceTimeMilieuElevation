#!/bin/bash

curl -i -X POST -d '{
	"latitudeDegreesKey": 30.3672,
	"latitudeHemisphereKey": "N",
	"longitudeDegreesKey": -97.7431,
	"longitudeHemisphereKey": "W",
	"datetimeKey": "2017-02-28T22:15:01+0600",
	"timezoneKey": "US/Central",
	"versionKey": 1
}' -H 'Content-type: application/json' https://ssldemo.linuxswift.com:8091/api

