extension CalculatorDocumentationArticle {
    static let conversionAndTimeSections: [DocumentationSection] = [
                DocumentationSection(
                    id: "calculator-units",
                    title: "Unit conversions",
                    blocks: [
                        .paragraph(
                            "calculator-units-summary",
                            "Use “to,” “in,” compact aliases, or natural questions. Commandly supports same-dimension conversion across length, area, volume, mass, temperature, duration, speed, acceleration, pressure, energy, power, frequency, storage, transfer rate, fuel economy, angle, torque, force, density, flow, electrical units, and illuminance."
                        ),
                        .examples("calculator-unit-examples", [
                            DocumentationExample(id: "calculator-unit-length", input: "10 km to miles", output: "about 6.2137 mi"),
                            DocumentationExample(id: "calculator-unit-height", input: "6 ft 2 in to cm", output: "187.96 cm"),
                            DocumentationExample(id: "calculator-unit-area", input: "1 acre in square feet", output: "43560 ft²"),
                            DocumentationExample(id: "calculator-unit-us-gallon", input: "1 gallon in liters", output: "about 3.7854 L", detail: "Unqualified gallon uses the exact US liquid definition and records that assumption."),
                            DocumentationExample(id: "calculator-unit-imperial-gallon", input: "1 imperial gallon in liters", output: "4.54609 L"),
                            DocumentationExample(id: "calculator-unit-mass", input: "150 pounds in kilograms", output: "about 68.0389 kg"),
                            DocumentationExample(id: "calculator-unit-temperature", input: "32 F in C", output: "0 °C"),
                            DocumentationExample(id: "calculator-unit-duration", input: "90 minutes in hours", output: "1.5 h"),
                            DocumentationExample(id: "calculator-unit-speed", input: "60 mph in km/h", output: "96.56064 km/h"),
                            DocumentationExample(id: "calculator-unit-pressure", input: "1 atmosphere in pascals", output: "101325 Pa"),
                            DocumentationExample(id: "calculator-unit-energy", input: "1 kWh in joules", output: "3600000 J"),
                            DocumentationExample(id: "calculator-unit-storage-decimal", input: "1 GB in MB", output: "1000 MB"),
                            DocumentationExample(id: "calculator-unit-storage-binary", input: "1 GiB in MiB", output: "1024 MiB"),
                            DocumentationExample(id: "calculator-unit-rate", input: "100 Mbps in MB/s", output: "12.5 MB/s"),
                            DocumentationExample(id: "calculator-unit-fuel", input: "30 mpg in liters per 100 km", output: "about 7.8405 L/100 km", detail: "Unqualified mpg uses US miles per gallon."),
                            DocumentationExample(id: "calculator-unit-angle", input: "pi radians in degrees", output: "180°"),
                            DocumentationExample(id: "calculator-unit-electric-power", input: "watts if volts are 120 and amps are 10", output: "1200 W"),
                            DocumentationExample(id: "calculator-unit-electric-current", input: "amps for 1500 watts at 120 volts", output: "12.5 A"),
                            DocumentationExample(id: "calculator-unit-illuminance", input: "10 foot candles in lux", output: "about 107.6391 lux"),
                        ]),
                        .bullets("calculator-unit-assumptions", [
                            "A duration year uses the mean Gregorian year of 365.2425 days and reports that assumption.",
                            "Speed of sound uses 343 m/s for dry air at 20 °C and reports the assumption.",
                            "US and Imperial volume and fuel-economy variants are distinct.",
                            "Electrical relationships include P = V × I, I = P ÷ V, and V = P ÷ I.",
                        ]),
                        .callout(
                            "calculator-unit-physical-safety",
                            DocumentationCallout(
                                kind: .important,
                                title: "No invented physical conversions",
                                text: "Cooking volume-to-mass needs ingredient density; months are not fixed durations; and lumens are not converted to lux without area and geometry. Commandly fails or explains the missing context instead of inventing a value."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-currency",
                    title: "Currency conversion",
                    blocks: [
                        .paragraph(
                            "calculator-currency-summary",
                            "Currency conversion accepts ISO codes, common names, compact forms, and unambiguous symbols. It uses live Frankfurter exchange-rate data with no API key, so the amount changes with the provider’s rate and timestamp."
                        ),
                        .examples("calculator-currency-examples", [
                            DocumentationExample(id: "calculator-currency-iso", input: "100 USD in EUR", detail: "Converts with the available USD/EUR rate."),
                            DocumentationExample(id: "calculator-currency-compact", input: "100USD in EUR", detail: "Spaces between the amount and source code are optional."),
                            DocumentationExample(id: "calculator-currency-name", input: "100 US dollars to Japanese yen"),
                            DocumentationExample(id: "calculator-currency-symbol", input: "€50 to USD", detail: "The euro symbol is unambiguous."),
                            DocumentationExample(id: "calculator-currency-addition", input: "100 USD + 50 EUR in USD", detail: "Every operand is converted into the requested output currency."),
                            DocumentationExample(id: "calculator-currency-rate-division", input: "100 USD divided by the EUR exchange rate", detail: "Uses an explicit EUR/source quote direction and records it in result metadata."),
                        ]),
                        .bullets("calculator-currency-rules", [
                            "The dollar sign is resolved only when the current locale region identifies a dollar currency such as USD, CAD, AUD, or NZD.",
                            "The yen sign needs Japanese or Chinese locale context; euro and pound symbols are unambiguous.",
                            "Generic names such as pesos and kr remain ambiguous; use an ISO code or region-qualified name.",
                            "If a required rate is missing, the complete calculation fails rather than mixing live and invented data.",
                        ]),
                        .callout(
                            "calculator-currency-network",
                            DocumentationCallout(
                                kind: .permission,
                                title: "Internet connection required",
                                text: "Currency is the calculator category that uses a network provider. Provider failures surface as an error; Commandly never fabricates an exchange rate."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-calendar",
                    title: "Dates and calendars",
                    blocks: [
                        .paragraph(
                            "calculator-calendar-summary",
                            "Date calculations use your current Calendar, locale, time zone, and the current date. Adding a month or year clamps an invalid month-end or leap day to the last valid day."
                        ),
                        .examples("calculator-calendar-examples", [
                            DocumentationExample(id: "calculator-calendar-relative-day", input: "3 days from now", detail: "Returns the date three calendar days after today."),
                            DocumentationExample(id: "calculator-calendar-relative-combined", input: "1 year 2 months 3 days from now"),
                            DocumentationExample(id: "calculator-calendar-specific", input: "90 days before December 25"),
                            DocumentationExample(id: "calculator-calendar-month-clamp", input: "January 31 plus 1 month", detail: "Clamps to the last valid day in February."),
                            DocumentationExample(id: "calculator-calendar-next-weekday", input: "next Monday", detail: "“Next” excludes today."),
                            DocumentationExample(id: "calculator-calendar-this-weekday", input: "this Wednesday", detail: "“This” can include today."),
                            DocumentationExample(id: "calculator-calendar-ordinal-weekday", input: "third Friday of next month"),
                            DocumentationExample(id: "calculator-calendar-boundary", input: "last day of this quarter"),
                            DocumentationExample(id: "calculator-calendar-difference", input: "days between January 1 and February 1", output: "31"),
                            DocumentationExample(id: "calculator-calendar-quarter", input: "current quarter"),
                            DocumentationExample(id: "calculator-calendar-business-days", input: "10 working days after July 1", detail: "Uses configured weekend weekdays and only explicitly supplied holidays."),
                            DocumentationExample(id: "calculator-calendar-age", input: "age if born July 15, 2000"),
                            DocumentationExample(id: "calculator-calendar-format-iso", input: "format July 15, 2026 as ISO", output: "2026-07-15"),
                            DocumentationExample(id: "calculator-calendar-timestamp", input: "July 15 2026 as unix timestamp"),
                        ]),
                        .bullets("calculator-calendar-rules", [
                            "Yearless holiday and month/day queries resolve using the current calendar context.",
                            "Business days use configured weekend days and supplied holiday dates; no regional holiday calendar is invented.",
                            "A “my birthday” query needs a birthday month/day supplied with consent. You can always include the date directly in the expression.",
                            "Numeric date interpretation follows the current locale and is attached to result metadata.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-time-zones",
                    title: "Clock math, time zones, schedules, and cron",
                    blocks: [
                        .paragraph(
                            "calculator-time-zones-summary",
                            "Clock and zone calculations are date-aware. Named zones use Foundation’s IANA time-zone identifiers and uniquely resolved city aliases, so daylight-saving offsets are calculated for the relevant date."
                        ),
                        .examples("calculator-time-zone-examples", [
                            DocumentationExample(id: "calculator-time-clock-add", input: "3 hours after 2pm", output: "5:00 PM"),
                            DocumentationExample(id: "calculator-time-clock-subtract", input: "noon minus 45 minutes", output: "11:15 AM"),
                            DocumentationExample(id: "calculator-time-combined", input: "2 hours 30 minutes after 5pm", output: "7:30 PM"),
                            DocumentationExample(id: "calculator-time-cross-midnight", input: "difference between 11pm and 2am", output: "3 hours", detail: "The end is treated as the next day and the assumption is reported."),
                            DocumentationExample(id: "calculator-time-format-duration", input: "150 minutes as hours and minutes", output: "2 h 30 min"),
                            DocumentationExample(id: "calculator-time-format-clock", input: "17:30 in 12-hour time", output: "5:30 PM"),
                            DocumentationExample(id: "calculator-time-current-zone", input: "current time in Tokyo"),
                            DocumentationExample(id: "calculator-time-zone-convert", input: "5pm New York in Tokyo", detail: "The date can change in the destination zone."),
                            DocumentationExample(id: "calculator-time-zone-date-aware", input: "5pm New York in London on March 10, 2026"),
                            DocumentationExample(id: "calculator-time-offset", input: "time in UTC+5:45", detail: "Whole-, half-, and quarter-hour UTC offsets are accepted."),
                            DocumentationExample(id: "calculator-time-iso", input: "2026-07-15T14:30:00-04:00 in UTC"),
                            DocumentationExample(id: "calculator-time-meeting", input: "how many 45-minute meetings fit between 9 and 5", output: "10"),
                            DocumentationExample(id: "calculator-time-shift", input: "8-hour shift starting at 9 with a 30-minute break", output: "5:30 PM"),
                            DocumentationExample(id: "calculator-time-recurrence", input: "next date in a biweekly schedule starting July 2"),
                            DocumentationExample(id: "calculator-time-cron-describe", input: "what does 0 0 * * * mean", output: "At 00:00 every day"),
                            DocumentationExample(id: "calculator-time-cron-next", input: "next run for 0 9 * * MON"),
                        ]),
                        .callout(
                            "calculator-time-zone-ambiguity",
                            DocumentationCallout(
                                kind: .important,
                                title: "Ambiguous abbreviations are rejected",
                                text: "CST, IST, BST, PST, EST, and similar abbreviations can identify multiple real zones or offsets. Use a city, geographic alias, IANA identifier, or explicit UTC offset instead."
                            )
                        ),
                    ]
                ),
    ]
}

