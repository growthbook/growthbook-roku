'
' GrowthBook SDK for Roku
' Official implementation for GrowthBook feature flags and A/B testing
' https://www.growthbook.io
'

' ===================================================================
' GrowthBook - Main class
' ===================================================================
function GrowthBook(config as object) as object
    instance = {
        ' Configuration
        apiHost: "https://cdn.growthbook.io",
        clientKey: "",
        decryptionKey: "",
        attributes: {},
        trackingCallback: invalid,
        onFeatureUsage: invalid,
        enableDevMode: false,
        enabled: true,
        qaMode: false,
        forcedVariations: {},
        
        ' Internal state
        features: {},
        cachedFeatures: {},
        savedGroups: {},
        _evaluationStack: [],
        _trackedExperiments: {},
        trackingPlugins: [],
        stickyBucketService: invalid,
        _stickyBucketAssignmentDocs: {},
        lastUpdate: 0,
        isInitialized: false,
        
        ' Network utilities
        http: invalid,
        
        ' Methods
        init: GrowthBook_init,
        setAttributes: GrowthBook_setAttributes,
        isOn: GrowthBook_isOn,
        getFeatureValue: GrowthBook_getFeatureValue,
        evalFeature: GrowthBook_evalFeature,
        refreshFeatures: GrowthBook_refreshFeatures,
        _loadFeaturesFromAPI: GrowthBook__loadFeaturesFromAPI,
        _parseFeatures: GrowthBook__parseFeatures,
        _evaluateConditions: GrowthBook__evaluateConditions,
        _evalConditionResult: GrowthBook__evalConditionResult,
        _evalOrResult: GrowthBook__evalOrResult,
        _savedGroupValues: GrowthBook__savedGroupValues,
        _getAttributeValue: GrowthBook__getAttributeValue,
        _fnv1a32: GrowthBook__fnv1a32,
        _longToStr: GrowthBook__longToStr,
        _gbhash: GrowthBook__gbhash,
        _paddedVersionString: GrowthBook__paddedVersionString,
        _isIncludedInRollout: GrowthBook__isIncludedInRollout,
        _getBucketRanges: GrowthBook__getBucketRanges,
        _chooseVariation: GrowthBook__chooseVariation,
        _inRange: GrowthBook__inRange,
        _toDouble: GrowthBook__toDouble,
        _deepEqual: GrowthBook__deepEqual,
        _compare: GrowthBook__compare,
        _jsonType: GrowthBook__jsonType,
        _isOrderable: GrowthBook__isOrderable,
        _valuesEqual: GrowthBook__valuesEqual,
        _isIn: GrowthBook__isIn,
        _isInAll: GrowthBook__isInAll,
        _trackExperiment: GrowthBook__trackExperiment,
        _trackFeatureUsage: GrowthBook__trackFeatureUsage,
        _evaluateExperiment: GrowthBook__evaluateExperiment,
        _inNamespace: GrowthBook__inNamespace,
        _getHashContext: GrowthBook__getHashContext,
        _isRuleIncluded: GrowthBook__isRuleIncluded,
        _log: GrowthBook__log,
        _hashAttribute: GrowthBook__hashAttribute,
        _decrypt: GrowthBook__decrypt,
        _notifyPlugins: GrowthBook__notifyPlugins,
        _getStickyBucketExperimentKey: GrowthBook__getStickyBucketExperimentKey,
        _getStickyBucketVariation: GrowthBook__getStickyBucketVariation,
        _saveStickyBucketAssignment: GrowthBook__saveStickyBucketAssignment,
        _createObject: function(name as string) as dynamic
            return CreateObject(name)
        end function,
        
        ' Public API
        registerTrackingPlugin: GrowthBook_registerTrackingPlugin,
        
        ' Helpers (exposed for internal use)
        toBoolean: GrowthBook_toBoolean
    }
    
    ' Apply config
    if type(config) = "roAssociativeArray"
        if config.apiHost <> invalid
            instance.apiHost = config.apiHost
        end if
        if config.clientKey <> invalid
            instance.clientKey = config.clientKey
        end if
        if config.decryptionKey <> invalid
            instance.decryptionKey = config.decryptionKey
        end if
        if config.attributes <> invalid
            instance.attributes = config.attributes
        end if
        if config.trackingCallback <> invalid
            instance.trackingCallback = config.trackingCallback
        end if
        if config.onFeatureUsage <> invalid
            instance.onFeatureUsage = config.onFeatureUsage
        end if
        if config.enableDevMode <> invalid
            instance.enableDevMode = config.enableDevMode
        end if
        if config.enabled <> invalid
            instance.enabled = config.enabled
        end if
        if config.qaMode <> invalid
            instance.qaMode = config.qaMode
        end if
        if config.features <> invalid
            instance.cachedFeatures = config.features
            instance.isInitialized = true
        end if
        if config.savedGroups <> invalid
            instance.savedGroups = config.savedGroups
        end if
        if config.forcedVariations <> invalid
            instance.forcedVariations = config.forcedVariations
        end if
        ' Parse URL for forced variations (e.g. ?my-experiment=1)
        if config.url <> invalid
            ' content.url might be available
            qs = ""
            urlParts = config.url.Split("?")
            if urlParts.Count() > 1
                qs = urlParts[1]
                ' Remove anchor if present
                anchorParts = qs.Split("#")
                if anchorParts.Count() > 0 then qs = anchorParts[0]
                
                ' Parse query string
                pairs = qs.Split("&")
                for each pair in pairs
                    kv = pair.Split("=")
                    if kv.Count() = 2
                        key = kv[0]
                        ' Decode URI component if needed? standard generic parsing usually enough for simple keys
                        ' Check if value is integer
                        valStr = kv[1]
                        valInt = Val(valStr) 
                        ' Val() returns 0 if not a number, but "0" is also 0. 
                        ' Valid variations are integers.
                        ' We need to know if it's a valid integer string.
                        ' Regex check or just permissive Val()
                        ' GrowthBook spec: value should be index of variation
                        instance.forcedVariations[key] = valInt
                    end if
                end for
            end if
        end if
        if config.trackingPlugins <> invalid
            instance.trackingPlugins = config.trackingPlugins
        end if
        if config.stickyBucketService <> invalid
            instance.stickyBucketService = config.stickyBucketService
        end if
        if config.stickyBucketAssignmentDocs <> invalid
            instance._stickyBucketAssignmentDocs = config.stickyBucketAssignmentDocs
        end if
    end if
    
    ' Configure HTTP transfer
    if config.http <> invalid
        instance.http = config.http
    else
        ' Try to create real roURLTransfer safely
        ' In some headless environments (like brs), this might throw or fail
        try
            instance.http = CreateObject("roURLTransfer")
        catch e
            instance.http = invalid
        end try
    end if
    
    if instance.http <> invalid and type(instance.http) = "roURLTransfer"
        instance.http.SetCertificatesFile("common:/certs/ca-bundle.crt")
        instance.http.AddHeader("Content-Type", "application/json")
        instance.http.AddHeader("User-Agent", "GrowthBook-Roku/1.4.1")
    end if
    
    return instance
end function

' ===================================================================
' Initialization - Load features from API or use provided features
' ===================================================================
function GrowthBook_init() as boolean
    if m.clientKey = "" and m.cachedFeatures.Count() = 0
        m._log("ERROR: clientKey is required or pass features directly")
        return false
    end if
    
    ' If we already have cached features, we're done
    if m.cachedFeatures.Count() > 0
        m.features = m.cachedFeatures
        m.isInitialized = true
        m._log("Features loaded from cache")
        return true
    end if
    
    ' Try to load from API
    if m.clientKey <> ""
        return m._loadFeaturesFromAPI()
    end if
    
    return false
end function

' ===================================================================
' Load features from GrowthBook API (async, non-blocking)
' ===================================================================
function GrowthBook__loadFeaturesFromAPI() as boolean
    apiUrl = m.apiHost + "/api/features/" + m.clientKey
    
    m._log("Loading features from: " + apiUrl)
    
    ' Setup async request with message port
    port = CreateObject("roMessagePort")
    m.http.SetMessagePort(port)
    m.http.SetUrl(apiUrl)
    
    ' Start async request
    if not m.http.AsyncGetToString()
        m._log("ERROR: Failed to start async request")
        return false
    end if
    
    ' Wait for response (10 second timeout)
    msg = Wait(10000, port)
    if msg = invalid
        m._log("ERROR: Request timed out")
        m.http.AsyncCancel()
        return false
    end if
    
    ' Handle response
    if type(msg) = "roUrlEvent"
        responseCode = msg.GetResponseCode()
        if responseCode <> 200
            m._log("ERROR: HTTP " + Str(responseCode).Trim())
            return false
        end if
        response = msg.GetString()
    else
        m._log("ERROR: Unexpected response type")
        return false
    end if
    
    if response = ""
        m._log("ERROR: Empty response")
        return false
    end if
    
    ' Parse response
    features = m._parseFeatures(response)
    
    if features <> invalid
        m.features = features
        m.cachedFeatures = features
        m.lastUpdate = CreateObject("roDateTime").AsSeconds()
        m.isInitialized = true
        m._log("Features loaded successfully: " + Str(features.Count()).Trim() + " features")
        return true
    end if
    
    return false
end function

' ===================================================================
' Parse features from JSON response (supports encrypted payloads)
' ===================================================================
function GrowthBook__parseFeatures(json as string) as object
    if json = ""
        return invalid
    end if
    
    ' Use Roku's built-in JSON parsing
    root = ParseJson(json)
    
    if root = invalid
        m._log("ERROR: Failed to parse features JSON")
        return invalid
    end if
    
    ' Check for encrypted features
    if root.encryptedFeatures <> invalid and root.encryptedFeatures <> ""
        if m.decryptionKey <> invalid and m.decryptionKey <> ""
            decrypted = m._decrypt(root.encryptedFeatures, m.decryptionKey)
            if decrypted <> ""
                decryptedFeatures = ParseJson(decrypted)
                if decryptedFeatures <> invalid
                    m.features = decryptedFeatures
                else
                    m._log("ERROR: Failed to parse decrypted features")
                    return invalid
                end if
            else
                m._log("ERROR: Failed to decrypt encryptedFeatures")
                return invalid
            end if
        else
            m._log("ERROR: encryptedFeatures present but no decryptionKey provided")
            return invalid
        end if
    end if

    ' Handle encrypted saved groups
    if root.encryptedSavedGroups <> invalid and root.encryptedSavedGroups <> "" and m.decryptionKey <> invalid and m.decryptionKey <> ""
        decrypted = m._decrypt(root.encryptedSavedGroups, m.decryptionKey)
        if decrypted <> ""
            decryptedGroups = ParseJson(decrypted)
            if decryptedGroups <> invalid
                m.savedGroups = decryptedGroups
            end if
        end if
    end if

    ' Handle saved groups from response (only if not encrypted)
    if root.encryptedSavedGroups = invalid and root.savedGroups <> invalid
        m.savedGroups = root.savedGroups
    end if
    
    ' Handle unencrypted features (only if not encrypted)
    if root.encryptedFeatures = invalid and root.features <> invalid
        m.features = root.features
        return m.features
    end if

    ' If we processed encryptedFeatures successfully, return them (even if empty)
    if root.encryptedFeatures <> invalid and root.encryptedFeatures <> ""
        return m.features
    end if
    
    ' Fallback: assume the response is already features object
    m.features = root
    return root
end function

' ===================================================================
' Check if a feature is enabled (boolean flag)
' ===================================================================
function GrowthBook_isOn(key as string) as boolean
    if m.features = invalid or m.features.Count() = 0
        return false
    end if
    
    feature = m.features[key]
    if feature = invalid
        return false
    end if
    
    ' If feature has defaultValue, it's a boolean feature
    if type(feature) = "roAssociativeArray"
        if feature.defaultValue <> invalid
            return GrowthBook_toBoolean(feature.defaultValue)
        end if
        ' If no defaultValue, check if it's enabled through experiment
        if feature.enabled = invalid
            return false
        end if
        return GrowthBook_toBoolean(feature.enabled)
    end if
    
    ' Direct value - coerce to boolean
    return GrowthBook_toBoolean(feature)
end function

' ===================================================================
' Get feature value with fallback
' ===================================================================
function GrowthBook_getFeatureValue(key as string, fallback as dynamic) as dynamic
    if m.features = invalid or m.features.Count() = 0
        return fallback
    end if
    
    feature = m.features[key]
    if feature = invalid
        return fallback
    end if
    
    ' If feature is an object with defaultValue
    if type(feature) = "roAssociativeArray"
        if feature.defaultValue <> invalid
            return feature.defaultValue
        end if
    end if
    
    ' Return feature value directly if it's not an object
    if type(feature) <> "roAssociativeArray"
        return feature
    end if
    
    return fallback
end function

' ===================================================================
' Evaluate a feature - returns full evaluation result
' ===================================================================
function GrowthBook_evalFeature(key as string) as object
    result = {
        key: key,
        value: invalid,
        on: false,
        off: true,
        source: "unknownFeature",
        ruleId: "",
        experimentId: "",
        variationId: -1,
        stickyBucketUsed: false
    }
    
    ' Check for cyclic prerequisites
    for each stackKey in m._evaluationStack
        if stackKey = key
            result.source = "cyclicPrerequisite"
            m._trackFeatureUsage(key, result)
            return result
        end if
    end for
    m._evaluationStack.Push(key)
    
    if m.features = invalid or m.features.Count() = 0
        result.source = "unknownFeature"
        m._evaluationStack.Pop()
        m._trackFeatureUsage(key, result)
        return result
    end if
    
    feature = m.features[key]
    if feature = invalid
        result.source = "unknownFeature"
        m._evaluationStack.Pop()
        m._trackFeatureUsage(key, result)
        return result
    end if
    
    result.source = "defaultValue"
    
    ' Handle feature object
    if type(feature) = "roAssociativeArray"
        if feature.rules <> invalid
            for each rule in feature.rules
                if type(rule) = "roAssociativeArray"
                    while true
                        ' 1. Prerequisites
                        skipRule = false
                        if rule.parentConditions <> invalid
                            for each parent in rule.parentConditions
                                parentResult = m.evalFeature(parent.id)
                                if parentResult.source = "cyclicPrerequisite"
                                    result.source = "cyclicPrerequisite"
                                    m._evaluationStack.Pop()
                                    m._trackFeatureUsage(key, result)
                                    return result
                                end if
                                
                                ' The condition alone decides; a gate only changes what a failure does
                                parentCondition = parent.condition
                                if parentCondition = invalid then parentCondition = {}
                                tempGB = GrowthBook({ attributes: { value: parentResult.value }, savedGroups: m.savedGroups, http: m.http })
                                if not tempGB._evaluateConditions(parentCondition)
                                    ' Only a gate blocks the feature; any other failing prerequisite skips this rule
                                    if not GrowthBook_toBoolean(parent.gate)
                                        skipRule = true
                                        exit for
                                    end if
                                    result.source = "prerequisite"
                                    m._evaluationStack.Pop()
                                    m._trackFeatureUsage(key, result)
                                    return result
                                end if
                            end for
                        end if
                        if skipRule then exit while
                        
                        ' 2. Rule Condition
                        if not m._evaluateConditions(rule.condition) then exit while
                        
                        ' Namespace check
                        if rule.namespace <> invalid
                            hashAttribute = "id"
                            if rule.hashAttribute <> invalid and rule.hashAttribute <> "" then hashAttribute = rule.hashAttribute
                            hashValue = m._getAttributeValue(hashAttribute)
                            if hashValue = invalid then exit while
                            if type(hashValue) <> "roString" and type(hashValue) <> "String"
                                hashValue = Str(hashValue).Trim()
                            end if
                            if hashValue = "" then exit while
                            if not m._inNamespace(hashValue, rule.namespace) then exit while
                        end if
                        
                        ' 3. Force Rule
                        if rule.DoesExist("force")
                            ' Handle coverage/range/filters/hashVersion for force rules
                            if not m._isRuleIncluded(rule, key) then exit while
                            
                            result.value = rule.force
                            result.on = GrowthBook_toBoolean(rule.force)
                            result.off = not result.on
                            result.source = "force"
                            if rule.ruleId <> invalid 
                                result.ruleId = rule.ruleId
                            else if rule.id <> invalid
                                result.ruleId = rule.id
                            end if
                            m._evaluationStack.Pop()
                            m._trackFeatureUsage(key, result)
                            return result
                        end if
                        
                        ' 4. Experiment Rule
                        if rule.variations <> invalid
                            expResult = m._evaluateExperiment(rule, result)
                            if expResult.source = "experiment"
                                ' Check for passthrough meta
                                if rule.meta <> invalid and expResult.variationId <> invalid
                                    variationMeta = rule.meta[expResult.variationId]
                                    if variationMeta <> invalid and variationMeta.passthrough = true
                                        exit while
                                    end if
                                end if
                                m._evaluationStack.Pop()
                                m._trackFeatureUsage(key, expResult)
                                return expResult
                            end if
                        end if
                        
                        exit while
                    end while
                end if
            end for
        end if
        
        ' Use default value
        result.source = "defaultValue"
        if feature.defaultValue <> invalid
            result.value = feature.defaultValue
            result.on = GrowthBook_toBoolean(feature.defaultValue)
            result.off = not result.on
        end if
    else
        ' Simple value
        result.value = feature
        result.on = GrowthBook_toBoolean(feature)
        result.off = not result.on
        result.source = "unknownFeature"
    end if
    
    m._evaluationStack.Pop()
    m._trackFeatureUsage(key, result)
    return result
end function

' ===================================================================
' Evaluate experiment variations
' ===================================================================
function GrowthBook__evaluateExperiment(rule as object, result as object) as object
    ' 1. Variations count check
    if rule.variations = invalid or rule.variations.Count() < 2
        return result
    end if
    
    ' 2. Global enabled check
    if m.enabled = false
        m._log("GrowthBook is globally disabled")
        return result
    end if

    ' 3. URL forced variations (querystring)
    ' (Implementation in init or elsewhere, but we check m.forcedVariations here)
    experimentKey = result.key
    if rule.key <> invalid then experimentKey = rule.key
    
    ' 4. Forced Variations (Global)
    if m.forcedVariations <> invalid and experimentKey <> invalid and m.forcedVariations[experimentKey] <> invalid
        forcedIndex = m.forcedVariations[experimentKey]
        if forcedIndex >= 0 and forcedIndex < rule.variations.Count()
            m._log("Forced variation (global): " + Str(forcedIndex).Trim())
            result.variationId = forcedIndex
            result.value = rule.variations[forcedIndex]
            result.on = GrowthBook_toBoolean(result.value)
            result.off = not result.on
            result.source = "experiment"
            if rule.ruleId <> invalid 
                result.ruleId = rule.ruleId
            else if rule.id <> invalid
                result.ruleId = rule.id
            end if
            if rule.key <> invalid
                result.experimentId = rule.key
            end if
            m._trackExperiment(rule, result)
            return result
        else
            ' Forced variation out of bounds, skip experiment
            m._log("Forced variation out of bounds (global): " + Str(forcedIndex).Trim())
            return result
        end if
    end if

    ' 5. Active check
    if rule.active = false
        m._log("Experiment is inactive")
        return result
    end if

    ' 6. Get hashing context and value
    context = m._getHashContext(rule, result.key)
    if not context.success then return result
    
    ' 7. Sticky Bucket Lookup
    stickyResult = m._getStickyBucketVariation(rule, result.key)
    assigned = stickyResult.variation
    stickyBucketVersionIsBlocked = stickyResult.versionIsBlocked
    foundStickyBucket = (assigned >= 0)

    if foundStickyBucket
        m._log("Found sticky bucket for experiment, variation: " + Str(assigned).Trim())
    else
        ' 8. Filters/Namespace/Condition Check (if no sticky)
        ' Filters and Namespace check (Rule inclusion)
        if not m._isRuleIncluded(rule, result.key)
            m._log("Experiment rule filtered out (inclusion)")
            return result
        end if

        ' Condition check
        if rule.condition <> invalid
            if not m._evaluateConditions(rule.condition)
                m._log("Experiment conditions failed")
                return result
            end if
        end if

        ' 8.1 Parent Conditions / Prerequisites (Prerequisites)
        if rule.parentConditions <> invalid
            for each parent in rule.parentConditions
                parentResult = m.evalFeature(parent.id)
                if parentResult.source = "cyclicPrerequisite"
                    m._log("Cyclic prerequisite detected")
                    return result
                end if
                
                parentCondition = parent.condition
                if parentCondition = invalid then parentCondition = {}
                tempGB = GrowthBook({ attributes: { value: parentResult.value }, savedGroups: m.savedGroups, http: m.http })
                if not tempGB._evaluateConditions(parentCondition)
                    m._log("Prerequisite failed")
                    return result
                end if
            end for
        end if
        
        ' 8.2 Groups check
        if rule.groups <> invalid and rule.groups.Count() > 0
            userGroups = m.attributes.groups
            if userGroups = invalid then userGroups = {}
            matched = false
            for each g in rule.groups
                if userGroups[g] = true
                    matched = true
                    exit for
                end if
            end for
            if not matched
                m._log("User not in required groups")
                return result
            end if
        end if

        ' Condition check
        if rule.condition <> invalid
            if not m._evaluateConditions(rule.condition)
                m._log("Experiment conditions failed")
                return result
            end if
        end if
    end if

    ' 9. Hash calculation and assignment
    n = m._gbhash(context.seed, context.hashValue, context.hashVersion)
    if n = invalid
        m._log("Invalid hash version")
        return result
    end if

    if not foundStickyBucket
        if rule.ranges <> invalid
            ranges = rule.ranges
        else
            coverage# = 1
            if rule.coverage <> invalid then coverage# = m._toDouble(rule.coverage)
            ranges = m._getBucketRanges(rule.variations.Count(), coverage#, rule.weights)
        end if
        assigned = m._chooseVariation(n, ranges)
    end if

    ' 10. Unenroll if sticky bucket version blocked
    if stickyBucketVersionIsBlocked
        m._log("Sticky bucket version blocked")
        result.stickyBucketUsed = true
        return result
    end if

    ' 11. Not in experiment
    if assigned < 0
        m._log("User not in experiment rollout")
        return result
    end if

    ' 12. Experiment Rule Force
    if rule.force <> invalid
        assigned = rule.force
        ' If forced, we skip QA mode check and go straight to result construction
    else
        ' 13. QA Mode check (only if not forced)
        if m.qaMode = true
            m._log("GrowthBook is in QA mode, skipping")
            return result
        end if
    end if

    ' 14. Build results
    inExperiment = true
    if assigned < 0 or assigned >= rule.variations.Count()
        assigned = -1
        inExperiment = false
    end if

    if assigned >= 0
        result.value = rule.variations[assigned]
        result.on = GrowthBook_toBoolean(result.value)
        result.off = not result.on
        result.variationId = assigned
    end if
    
    result.inExperiment = inExperiment
    result.source = "experiment"
    result.hashUsed = true
    result.bucket = n
    if stickyResult.variation >= 0 then result.stickyBucketUsed = true
    
    ' 14.5 Persist sticky bucket
    if inExperiment and (result.stickyBucketUsed <> true or stickyResult.source = "fallback")
        m._saveStickyBucketAssignment(rule, context, assigned, result.key)
    end if
    
    if rule.ruleId <> invalid 
        result.ruleId = rule.ruleId
    else if rule.id <> invalid
        result.ruleId = rule.id
    end if
    if rule.key <> invalid
        result.experimentId = rule.key
    end if

    ' 15. Tracking
    m._trackExperiment(rule, result)
    
    return result
end function


' ===================================================================
' Set user attributes for targeting and experiments
' ===================================================================
sub GrowthBook_setAttributes(attrs as object)
    if type(attrs) = "roAssociativeArray"
        m.attributes = attrs
        m._log("Attributes updated")
    end if
end sub

' ===================================================================
' Refresh features from the GrowthBook API
' Call this when you want to fetch updated features on-demand
' Note: BrightScript is single-threaded, so automatic polling is not possible
' ===================================================================
function GrowthBook_refreshFeatures() as boolean
    if m.clientKey = "" or m.clientKey = invalid
        m._log("ERROR: clientKey required for refresh")
        return false
    end if
    
    if m.http = invalid
        m._log("ERROR: HTTP not available")
        return false
    end if
    
    return m._loadFeaturesFromAPI()
end function

' ===================================================================
' Get attribute value (supports nested paths like "user.age")
' ===================================================================
function GrowthBook__getAttributeValue(attr as string) as dynamic
    ' Check for nested path (e.g., "father.age")
    if Instr(1, attr, ".") > 0
        parts = attr.Split(".")
        value = m.attributes
        
        for each part in parts
            if type(value) = "roAssociativeArray" and value.DoesExist(part)
                value = value[part]
            else
                return invalid
            end if
        end for
        
        return value
    end if
    
    ' Simple attribute
    if m.attributes.DoesExist(attr)
        return m.attributes[attr]
    end if
    
    return invalid
end function

' ===================================================================
' Evaluate conditions (rules) against user attributes
' Passes only when the condition is known to pass: a condition that
' depends on an operator or saved group type this SDK doesn't support fails
' ===================================================================
function GrowthBook__evaluateConditions(condition as object) as boolean
    r = m._evalConditionResult(condition)
    if r = invalid then return false
    return r
end function

' ===================================================================
' Evaluate a condition to true, false, or invalid when the result depends on
' an operator or saved group type this SDK doesn't support. A false entry
' decides the condition wherever an unsupported one is
' ===================================================================
function GrowthBook__evalConditionResult(condition as object) as dynamic
    if condition = invalid
        return true
    end if
    
    if type(condition) <> "roAssociativeArray"
        return false
    end if
    
    ' Empty condition always passes
    if condition.Count() = 0
        return true
    end if
    
    ' Process all conditions - ALL must pass (AND logic at top level)
    result = true
    for each attr in condition
        ' Handle logical operators
        if attr = "$or"
            r = m._evalOrResult(condition["$or"])
            if r = invalid
                result = invalid
            else if not r
                return false
            end if
            continue for
        end if
        
        if attr = "$nor"
            r = m._evalOrResult(condition["$nor"])
            if r = invalid
                result = invalid
            else if r
                return false
            end if
            continue for
        end if
        
        if attr = "$and"
            if type(condition["$and"]) <> "roArray"
                continue for
            end if
            for each subcond in condition["$and"]
                r = m._evalConditionResult(subcond)
                if r = invalid
                    result = invalid
                else if not r
                    return false
                end if
            end for
            continue for
        end if
        
        if attr = "$not"
            r = m._evalConditionResult(condition["$not"])
            if r = invalid
                result = invalid
            else if r
                return false
            end if
            continue for
        end if
        
        ' Handle attribute conditions
        
        value = m._getAttributeValue(attr)
        condition_value = condition[attr]
        
        ' An object whose keys all start with "$" holds operators. Any other
        ' object, including one mixing operators and fields, is a plain value
        isOperatorObject = false
        if type(condition_value) = "roAssociativeArray"
            isOperatorObject = true
            for each key in condition_value
                if Left(key, 1) <> "$"
                    isOperatorObject = false
                    exit for
                end if
            end for
        end if
        
        if isOperatorObject
            ' Operator conditions. An empty object has no operators, so it passes.
            ' Operators are looked up by key, so a null argument is still checked
            valueUnknown = false
            if condition_value.DoesExist("$eq")
                if not m._valuesEqual(value, condition_value["$eq"])
                    return false
                end if
            end if
            if condition_value.DoesExist("$ne")
                if m._valuesEqual(value, condition_value["$ne"])
                    return false
                end if
            end if
            if condition_value.DoesExist("$lt")
                if not m._compare(value, condition_value["$lt"], "$lt") then return false
            end if
            if condition_value.DoesExist("$lte")
                if not m._compare(value, condition_value["$lte"], "$lte") then return false
            end if
            if condition_value.DoesExist("$gt")
                if not m._compare(value, condition_value["$gt"], "$gt") then return false
            end if
            if condition_value.DoesExist("$gte")
                if not m._compare(value, condition_value["$gte"], "$gte") then return false
            end if
            if condition_value.DoesExist("$veq")
                ' Version equals
                if not m._isOrderable(value, condition_value["$veq"]) then return false
                v1 = m._paddedVersionString(value)
                v2 = m._paddedVersionString(condition_value["$veq"])
                if v1 <> v2
                    return false
                end if
            end if
            if condition_value.DoesExist("$vne")
                ' Version not equals
                ' A type mismatch is "not equal", so $vne passes
                if m._isOrderable(value, condition_value["$vne"])
                    v1 = m._paddedVersionString(value)
                    v2 = m._paddedVersionString(condition_value["$vne"])
                    if v1 = v2
                        return false
                    end if
                end if
            end if
            if condition_value.DoesExist("$vlt")
                ' Version less than
                if not m._isOrderable(value, condition_value["$vlt"]) then return false
                v1 = m._paddedVersionString(value)
                v2 = m._paddedVersionString(condition_value["$vlt"])
                if not (v1 < v2)
                    return false
                end if
            end if
            if condition_value.DoesExist("$vlte")
                ' Version less than or equal
                if not m._isOrderable(value, condition_value["$vlte"]) then return false
                v1 = m._paddedVersionString(value)
                v2 = m._paddedVersionString(condition_value["$vlte"])
                if not (v1 <= v2)
                    return false
                end if
            end if
            if condition_value.DoesExist("$vgt")
                ' Version greater than
                if not m._isOrderable(value, condition_value["$vgt"]) then return false
                v1 = m._paddedVersionString(value)
                v2 = m._paddedVersionString(condition_value["$vgt"])
                if not (v1 > v2)
                    return false
                end if
            end if
            if condition_value.DoesExist("$vgte")
                ' Version greater than or equal
                if not m._isOrderable(value, condition_value["$vgte"]) then return false
                v1 = m._paddedVersionString(value)
                v2 = m._paddedVersionString(condition_value["$vgte"])
                if not (v1 >= v2)
                    return false
                end if
            end if
            if condition_value.DoesExist("$in")
                if type(condition_value["$in"]) <> "roArray" then return false
                if not m._isIn(value, condition_value["$in"], false) then return false
            end if
            if condition_value.DoesExist("$ini")
                if type(condition_value["$ini"]) <> "roArray" then return false
                if not m._isIn(value, condition_value["$ini"], true) then return false
            end if
            if condition_value.DoesExist("$nin")
                if type(condition_value["$nin"]) <> "roArray" then return false
                if m._isIn(value, condition_value["$nin"], false) then return false
            end if
            if condition_value.DoesExist("$nini")
                if type(condition_value["$nini"]) <> "roArray" then return false
                if m._isIn(value, condition_value["$nini"], true) then return false
            end if
            if condition_value.DoesExist("$type")
                ' Check if actual type matches expected type
                expectedType = condition_value["$type"]
                actualType = type(value)
                
                ' Map BrightScript types to JSON types
                jsonType = ""
                if actualType = "roString" or actualType = "String" then jsonType = "string"
                if actualType = "roInteger" or actualType = "roFloat" or actualType = "Integer" or actualType = "Float" then jsonType = "number"
                if actualType = "roBoolean" or actualType = "Boolean" then jsonType = "boolean"
                if actualType = "roArray" then jsonType = "array"
                if actualType = "roAssociativeArray" then jsonType = "object"
                if actualType = "Invalid" or value = invalid then jsonType = "null"
                
                if jsonType <> expectedType
                    return false
                end if
            end if
            if condition_value.DoesExist("$exists")
                ' Check if attribute exists
                shouldExist = GrowthBook_toBoolean(condition_value["$exists"])
                exists = (value <> invalid)
                if exists <> shouldExist
                    return false
                end if
            end if
            for each regexOp in ["$regex", "$regexi"]
                if condition_value.DoesExist(regexOp)
                    ' Regex matching
                    if value = invalid or (type(value) <> "roString" and type(value) <> "String")
                        return false
                    end if
                    pattern = condition_value[regexOp]
                    if type(pattern) <> "roString" and type(pattern) <> "String"
                        return false
                    end if
                    ' Reject patterns with invalid quantifier sequences (crashes roRegex)
                    firstChar = Left(pattern, 1)
                    if firstChar = "?" or firstChar = "*" or firstChar = "+"
                        return false
                    end if
                    if Instr(1, pattern, "**") > 0 or Instr(1, pattern, "++") > 0 or Instr(1, pattern, "???") > 0
                        return false
                    end if
                    ' $regexi matches case-insensitively
                    regexFlags = ""
                    if regexOp = "$regexi" then regexFlags = "i"
                    ' Use CreateObject("roRegex") for pattern matching
                    try
                        regex = CreateObject("roRegex", pattern, regexFlags)
                        if regex = invalid or not regex.IsMatch(value)
                            return false
                        end if
                    catch e
                        ' Invalid regex pattern - fail the condition
                        return false
                    end try
                end if
            end for
            if condition_value.DoesExist("$elemMatch")
                ' Array element matching
                if value = invalid or type(value) <> "roArray"
                    return false
                end if
                expected = condition_value["$elemMatch"]
                if type(expected) <> "roAssociativeArray"
                    return false
                end if
                ' Operators test each element itself. A condition, including one
                ' that only uses $or, $and, $nor or $savedGroup, tests each
                ' element's fields
                perElement = true
                for each key in expected
                    if Left(key, 1) <> "$" or key = "$or" or key = "$and" or key = "$nor" or key = "$savedGroup"
                        perElement = false
                        exit for
                    end if
                end for
                matched = false
                ' Create temp instance once outside loop for performance
                tempGB = GrowthBook({ attributes: {}, savedGroups: m.savedGroups, http: {} })
                for each item in value
                    ' Only skip null elements; 0, "" and false are still tested
                    if item <> invalid
                        if perElement
                            tempGB.attributes = { "_": item }
                            tempCond = { "_": expected }
                        else
                            ' A non-object element has no fields, so every path is missing
                            if type(item) = "roAssociativeArray"
                                tempGB.attributes = item
                            else
                                tempGB.attributes = {}
                            end if
                            tempCond = expected
                        end if
                        r = tempGB._evalConditionResult(tempCond)
                        if r = invalid
                            matched = invalid
                        else if r
                            matched = true
                            exit for
                        end if
                    end if
                end for
                if matched = invalid
                    valueUnknown = true
                else if not matched
                    return false
                end if
            end if
            if condition_value.DoesExist("$size")
                if type(value) <> "roArray"
                    return false
                end if
                expectedSize = condition_value["$size"]
                actualSize = value.Count()
                if type(expectedSize) = "roAssociativeArray"
                    ' Nested size condition - create temp GB with size as attribute
                    tempGB = GrowthBook({ attributes: { "_size": actualSize }, savedGroups: m.savedGroups, http: {} })
                    r = tempGB._evalConditionResult({ "_size": expectedSize })
                    if r = invalid
                        valueUnknown = true
                    else if not r
                        return false
                    end if
                else
                    ' Direct size comparison
                    if not m._valuesEqual(actualSize, expectedSize)
                        return false
                    end if
                end if
            end if
            for each allOp in ["$all", "$alli"]
                if condition_value.DoesExist(allOp)
                    ' All elements must be present ($alli ignores case)
                    if type(value) <> "roArray" or type(condition_value[allOp]) <> "roArray"
                        return false
                    end if
                    r = m._isInAll(value, condition_value[allOp], allOp = "$alli")
                    if r = invalid
                        valueUnknown = true
                    else if not r
                        return false
                    end if
                end if
            end for
            for each groupOp in ["$inGroup", "$notInGroup"]
                if condition_value.DoesExist(groupOp)
                    groupId = condition_value[groupOp]
                    if type(groupId) <> "roString" and type(groupId) <> "String"
                        return false
                    end if
                    groupValues = m._savedGroupValues(groupId)
                    if groupValues = invalid
                        ' A group type added after this SDK was built
                        valueUnknown = true
                    else if type(groupValues) <> "roArray"
                        ' A condition group or a malformed entry matches nobody
                        return false
                    else
                        ' Same membership as $in: an array attribute needs one shared element
                        found = m._isIn(value, groupValues, false)
                        if found <> (groupOp = "$inGroup")
                            return false
                        end if
                    end if
                end if
            end for
            if condition_value.DoesExist("$not")
                ' Negation operator on attribute value
                tempGB = GrowthBook({ attributes: m.attributes, savedGroups: m.savedGroups, http: {} })
                tempCondition = {}
                tempCondition[attr] = condition_value["$not"]
                r = tempGB._evalConditionResult(tempCondition)
                if r = invalid
                    valueUnknown = true
                else if r
                    return false
                end if
            end if
            
            knownOps = ["$eq", "$ne", "$lt", "$lte", "$gt", "$gte", "$veq", "$vne", "$vlt", "$vlte", "$vgt", "$vgte", "$in", "$ini", "$nin", "$nini", "$exists", "$type", "$regex", "$regexi", "$elemMatch", "$size", "$all", "$alli", "$inGroup", "$notInGroup", "$not"]
            for each key in condition_value
                ' Keys that belong on a condition, not on a value, never match
                if key = "$or" or key = "$and" or key = "$nor" or key = "$savedGroup"
                    return false
                end if
                isKnown = false
                for each op in knownOps
                    if key = op
                        isKnown = true
                        exit for
                    end if
                end for
                ' An operator this SDK doesn't support: the client's SDK may
                if not isKnown then valueUnknown = true
            end for
            
            if valueUnknown then result = invalid
        else
            ' Direct equality
            if not m._deepEqual(value, condition_value)
                return false
            end if
        end if
    end for
    
    return result
end function

' ===================================================================
' $or: true if any condition passes, invalid if none passes but one is
' unknown, false otherwise. An empty or non-array list passes, as in JS
' ===================================================================
function GrowthBook__evalOrResult(conditions as dynamic) as dynamic
    if type(conditions) <> "roArray" then return true
    if conditions.Count() = 0 then return true
    result = false
    for each subcond in conditions
        r = m._evalConditionResult(subcond)
        if r = invalid
            result = invalid
        else if r
            return true
        end if
    end for
    return result
end function

' ===================================================================
' Values of a saved group for $inGroup / $notInGroup: an array, false for a
' group that matches nobody (a condition group or a malformed entry), or
' invalid for a group type added after this SDK was built. An unknown id
' behaves like an empty list
' ===================================================================
function GrowthBook__savedGroupValues(groupId as string) as dynamic
    if m.savedGroups = invalid or not m.savedGroups.DoesExist(groupId) then return []
    entry = m.savedGroups[groupId]
    if type(entry) = "roArray" then return entry
    if type(entry) <> "roAssociativeArray" then return false
    groupType = entry["type"]
    if type(groupType) = "roString" or type(groupType) = "String"
        if groupType = "list"
            if type(entry["values"]) = "roArray" then return entry["values"]
            return false
        end if
        if groupType = "condition" then return false
    end if
    return invalid
end function

' ===================================================================
' FNV-1a 32-bit hash algorithm
' Returns integer hash value
' ===================================================================
function GrowthBook__fnv1a32(str as string) as longinteger
    ' FNV-1a constants
    hval& = &h811C9DC5&  ' 2166136261 - offset basis
    prime& = &h01000193&  ' 16777619 - FNV prime
    
    ' Process each character
    for i = 0 to str.Len() - 1
        charCode& = Asc(Mid(str, i + 1, 1))
        ' Bitwise XOR: (a OR b) - (a AND b)
        hval& = (hval& OR charCode&) - (hval& AND charCode&)
        hval& = (hval& * prime&) AND &hFFFFFFFF&  ' Keep 32-bit
    end for
    
    return hval&
end function

' ===================================================================
' Convert LongInteger to string without using Str()
' Avoids Str() coercing LongInteger to Float (32-bit),
' which loses precision for values > 7 significant digits
' ===================================================================
function GrowthBook__longToStr(val as longinteger) as string
    if val = 0 then return "0"
    result = ""
    remaining& = val
    while remaining& > 0
        digit% = remaining& mod 10
        result = Chr(48 + digit%) + result
        remaining& = remaining& \ 10
    end while
    return result
end function

' ===================================================================
' GrowthBook hash function with seed and version support
' Supports v1 and v2 hash algorithms for consistent bucketing
' Returns value between 0 and 1
' ===================================================================
function GrowthBook__gbhash(seed as string, value as string, version as integer) as dynamic
    ' Convert to string if needed
    if type(value) <> "roString" and type(value) <> "String"
        value = Str(value).Trim()
    end if
    if type(seed) <> "roString" and type(seed) <> "String"
        seed = ""
    end if
    
    if version = 2
        ' Version 2: fnv1a32(str(fnv1a32(seed + value)))
        combined = seed + value
        hash1& = m._fnv1a32(combined)
        hash2& = m._fnv1a32(m._longToStr(hash1&))
        return (hash2& MOD 10000) / 10000#
    else if version = 1
        ' Version 1: fnv1a32(value + seed)
        combined = value + seed
        hash1& = m._fnv1a32(combined)
        return (hash1& MOD 1000) / 1000#
    end if
    
    return invalid
end function

' ===================================================================
' Version string padding for semantic version comparison
' Enables comparisons like "1.4.0" > "1.3.9" and "1.0.0" > "1.0.0-beta"
' ===================================================================
function GrowthBook__paddedVersionString(input as dynamic) as string
    ' Convert to string if number
    if m._jsonType(input) = "number"
        input = Str(input).Trim()
    end if
    
    if m._jsonType(input) <> "string" or input = ""
        input = "0"
    end if
    
    version = input
    
    ' Remove leading "v" if present
    if Left(version, 1) = "v" or Left(version, 1) = "V"
        version = Mid(version, 2)
    end if
    
    ' Remove build info after "+" (e.g., "1.2.3+build123" -> "1.2.3")
    plusPos = Instr(1, version, "+")
    if plusPos > 0
        version = Left(version, plusPos - 1)
    end if
    
    ' Split on "." and "-"
    parts = []
    current = ""
    
    for i = 0 to version.Len() - 1
        char = Mid(version, i + 1, 1)
        if char = "." or char = "-"
            ' Keep empty segments, like the JS SDK ("1..2" has 3 parts)
            parts.Push(current)
            current = ""
        else
            current = current + char
        end if
    end for
    
    parts.Push(current)
    
    ' If exactly 3 parts (SemVer without pre-release), add "~"
    ' This makes "1.0.0" > "1.0.0-beta" since "~" is largest ASCII char
    if parts.Count() = 3
        parts.Push("~")
    end if
    
    ' Pad numeric parts with spaces (right-justify to 5 chars)
    result = ""
    for i = 0 to parts.Count() - 1
        part = parts[i]
        
        ' Check if part is numeric
        isNumeric = true
        if part.Len() = 0
            isNumeric = false
        else
            for j = 0 to part.Len() - 1
                charCode = Asc(Mid(part, j + 1, 1))
                if charCode < 48 or charCode > 57  ' Not 0-9
                    isNumeric = false
                    exit for
                end if
            end for
        end if
        
        ' Pad numeric parts with spaces
        if isNumeric
            while part.Len() < 5
                part = " " + part
            end while
        end if
        
        if i > 0 then result = result + "-"
        result = result + part
    end for
    
    return result
end function

' ===================================================================
' Check if user is included in rollout based on coverage
' Used for feature percentage rollouts (force rules with coverage)
' Note: Experiments use _getBucketRanges instead
' ===================================================================
function GrowthBook__isIncludedInRollout(seed as string, hashValue as string, hashVersion as integer, coverage as double) as boolean
    ' Coverage of 1 or more includes everyone
    if coverage >= 1 then return true
    
    ' Coverage of 0 or less excludes everyone
    if coverage <= 0 then return false
    
    ' Calculate hash for this user
    n = m._gbhash(seed, hashValue, hashVersion)
    if n = invalid then return false
    
    ' Half-open, like bucket ranges: a coverage of k/10000 includes exactly k buckets
    return n < coverage
end function

' ===================================================================
' Get bucket ranges for variation assignment
' Converts weights and coverage into [start, end) ranges
' ===================================================================
function GrowthBook__getBucketRanges(numVariations as integer, coverage as double, weights as object) as object
    ' Return empty ranges if no variations
    if numVariations < 1 then return []
    
    ' Clamp coverage to valid range [0, 1]
    if coverage < 0 then coverage = 0
    if coverage > 1 then coverage = 1
    
    ' Weights come from JSON as single-precision Floats; widen them so the
    ' range math below matches the double-precision JS SDK exactly
    doubleWeights = []
    if weights <> invalid
        for each w in weights
            doubleWeights.Push(m._toDouble(w))
        end for
    end if
    weights = doubleWeights
    
    ' Generate equal weights if not provided or invalid
    ' Equal weights = each variation gets 1/n of traffic
    if weights.Count() = 0 or weights.Count() <> numVariations
        equalWeight# = 1# / numVariations
        weights = []
        for i = 0 to numVariations - 1
            weights.Push(equalWeight#)
        end for
    end if
    
    ' Validate weights sum (should be ~1.0)
    weightSum# = 0
    for each w in weights
        weightSum# = weightSum# + w
    end for
    if weightSum# < 0.99# or weightSum# > 1.01#
        equalWeight# = 1# / numVariations
        weights = []
        for i = 0 to numVariations - 1
            weights.Push(equalWeight#)
        end for
    end if
    
    ' Build bucket ranges as [start, end] arrays
    ranges = []
    cumulative# = 0
    for each w in weights
        rangeStart# = cumulative#
        cumulative# = cumulative# + w
        ' Apply coverage: reduces each bucket by coverage percentage
        rangeEnd# = rangeStart# + coverage * w
        ranges.Push([rangeStart#, rangeEnd#])
    end for
    
    return ranges
end function

' ===================================================================
' Choose variation based on hash value and bucket ranges
' Returns variation index, or -1 if not in any bucket
' ===================================================================
function GrowthBook__chooseVariation(n as double, ranges as object) as integer
    for i = 0 to ranges.Count() - 1
        if m._inRange(n, ranges[i])
            return i
        end if
    end for
    return -1
end function

' ===================================================================
' Check if value is within a bucket range [start, end)
' Range is array: [0] = start, [1] = end
' ===================================================================
function GrowthBook__inRange(n as double, range as object) as boolean
    return n >= m._toDouble(range[0]) and n < m._toDouble(range[1])
end function

' ===================================================================
' Widen a JSON number to Double for bucketing math
' ParseJson returns single-precision Floats (unless the Roku OS 14.6+ "d"
' flag is used), so a weight of 0.2 arrives as 0.20000000298... Widening
' that directly would leave range ends ~1e-9 away from the JS SDK's doubles.
' Instead, find the shortest decimal that round-trips to the same Float and
' build the Double from that decimal. This reproduces the JS value exactly
' for anything with up to 7 significant digits (0.2, 0.5999, 0.0001, ...).
' Limitation: values that need more digits (e.g. 1/3) are only accurate to
' Float precision because the parser already discarded the extra digits.
' ===================================================================
function GrowthBook__toDouble(value as dynamic) as double
    t = type(value)
    if t = "roDouble" or t = "Double" then return value
    if t = "roString" or t = "String" then value = Val(value)
    t = type(value)
    if t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger"
        d# = value
        return d#
    end if
    if t <> "roFloat" and t <> "Float" then return 0
    
    f! = value
    neg = f! < 0
    if neg then f! = -f!
    d# = f!
    scale# = 1
    for p = 0 to 15
        mantissa& = d# * scale# + 0.5#
        candidate# = mantissa& / scale#
        check! = candidate#
        if check! = f!
            d# = candidate#
            exit for
        end if
        scale# = scale# * 10#
    end for
    if neg then d# = -d#
    return d#
end function

' ===================================================================
' Comparison helper with type coercion
' ===================================================================
function GrowthBook__compare(v1 as dynamic, v2 as dynamic, op as string) as boolean
    ' No coercion: both sides must be numbers, or both strings (compared as text)
    if not m._isOrderable(v1, v2) then return false
    
    if op = "$lt" then return v1 < v2
    if op = "$lte" then return v1 <= v2
    if op = "$gt" then return v1 > v2
    if op = "$gte" then return v1 >= v2
    
    return false
end function

' ===================================================================
' JSON type of a value: "string", "number", "boolean", "array", "object" or "null"
' ===================================================================
function GrowthBook__jsonType(value as dynamic) as string
    t = type(value)
    if t = "roString" or t = "String" then return "string"
    if t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then return "number"
    if t = "roBoolean" or t = "Boolean" then return "boolean"
    if t = "roArray" then return "array"
    if t = "roAssociativeArray" then return "object"
    if t = "Invalid" or t = "roInvalid" or t = "<uninitialized>" then return "null"
    return "unknown"
end function

' ===================================================================
' True when both values are numbers, or both are strings
' Booleans, null and mismatched types are not ordered
' ===================================================================
function GrowthBook__isOrderable(v1 as dynamic, v2 as dynamic) as boolean
    t = m._jsonType(v1)
    return (t = "number" or t = "string") and t = m._jsonType(v2)
end function

' ===================================================================
' Strict equality, as JS === on parsed JSON: different JSON types are never
' equal, and an array or object never equals one parsed separately, even
' with the same contents. Plain-value conditions use _deepEqual instead
' ===================================================================
function GrowthBook__valuesEqual(v1 as dynamic, v2 as dynamic) as boolean
    t = m._jsonType(v1)
    if t <> m._jsonType(v2) then return false
    if t = "null" then return true
    if t = "array" or t = "object" then return false
    return v1 = v2
end function

' ===================================================================
' True when actual (or, for an array, any of its elements) equals an
' element of expected. With insensitive, strings are compared ignoring case.
' ===================================================================
function GrowthBook__isIn(actual as dynamic, expected as object, insensitive as boolean) as boolean
    values = [actual]
    if type(actual) = "roArray" then values = actual
    for each v in values
        for each e in expected
            if insensitive and m._jsonType(v) = "string" and m._jsonType(e) = "string"
                if LCase(v) = LCase(e) then return true
            else if m._valuesEqual(v, e)
                return true
            end if
        end for
    end for
    return false
end function

' ===================================================================
' $all / $alli: true when every condition in expected passes for at least
' one element of actual, invalid when none fails but one depends on an
' operator this SDK doesn't support, false otherwise. Each condition can be
' a value or an operator object. With insensitive, a string value is
' compared ignoring case
' ===================================================================
function GrowthBook__isInAll(actual as object, expected as object, insensitive as boolean) as dynamic
    tempGB = GrowthBook({ attributes: {}, savedGroups: m.savedGroups, http: {} })
    result = true
    for each required in expected
        passed = false
        for each item in actual
            if insensitive and m._jsonType(required) = "string"
                r = false
                if m._jsonType(item) = "string" then r = (LCase(item) = LCase(required))
            else
                tempGB.attributes = { "_": item }
                r = tempGB._evalConditionResult({ "_": required })
            end if
            if r = invalid
                passed = invalid
            else if r
                passed = true
                exit for
            end if
        end for
        if passed = invalid
            result = invalid
        else if not passed
            return false
        end if
    end for
    return result
end function

' ===================================================================
' Deep equality check for values
' Handles null, primitives, arrays, and objects
' ===================================================================
function GrowthBook__deepEqual(val1 as dynamic, val2 as dynamic) as boolean
    ' Handle null/invalid
    if val1 = invalid and val2 = invalid
        return true
    end if
    if val1 = invalid or val2 = invalid
        return false
    end if
    
    ' JSON type must match, so "10" never equals 10
    type1 = m._jsonType(val1)
    if type1 <> m._jsonType(val2)
        return false
    end if
    
    ' Primitives
    if type1 = "string" or type1 = "number" or type1 = "boolean"
        return val1 = val2
    end if
    
    ' Arrays
    if type1 = "array"
        if val1.Count() <> val2.Count()
            return false
        end if
        for i = 0 to val1.Count() - 1
            if not m._deepEqual(val1[i], val2[i])
                return false
            end if
        end for
        return true
    end if
    
    ' Objects
    if type1 = "object"
        ' Check if all keys in val1 exist in val2 with same values
        for each key in val1
            if not val2.DoesExist(key)
                return false
            end if
            if not m._deepEqual(val1[key], val2[key])
                return false
            end if
        end for
        ' Check if val2 has any extra keys
        for each key in val2
            if not val1.DoesExist(key)
                return false
            end if
        end for
        return true
    end if
    
    ' Default: use equality
    return val1 = val2
end function

' ===================================================================
' Track experiment exposure (with de-duplication)
' ===================================================================
sub GrowthBook__trackExperiment(experiment as object, result as object)
    ' Build unique tracking key to prevent duplicate tracking
    hashAttribute = "id"
    if experiment.hashAttribute <> invalid then hashAttribute = experiment.hashAttribute
    hashValue = ""
    if m.attributes[hashAttribute] <> invalid
        attrValue = m.attributes[hashAttribute]
        if type(attrValue) = "roString" or type(attrValue) = "String"
            hashValue = attrValue
        else
            hashValue = Str(attrValue).Trim()
        end if
    end if
    experimentKey = ""
    if experiment.key <> invalid then experimentKey = experiment.key
    variationId = ""
    if result.variationId <> invalid
        if type(result.variationId) = "roString" or type(result.variationId) = "String"
            variationId = result.variationId
        else
            variationId = Str(result.variationId).Trim()
        end if
    end if
    
    trackingKey = hashAttribute + "|" + hashValue + "|" + experimentKey + "|" + variationId
    
    ' Skip if already tracked (applies to both callback and plugins)
    if m._trackedExperiments.DoesExist(trackingKey)
        return
    end if
    
    ' Mark as tracked
    m._trackedExperiments[trackingKey] = true
    
    ' Call the tracking callback if set
    if m.trackingCallback <> invalid
        m.trackingCallback(experiment, result)
    end if
    
    ' Notify tracking plugins
    m._notifyPlugins("experimentViewed", { experiment: experiment, result: result })
end sub

' ===================================================================
' Check if user is in a namespace
' ===================================================================
function GrowthBook__inNamespace(userId as string, namespace as object) as boolean
    if namespace = invalid or type(namespace) <> "roArray" or namespace.Count() <> 3
        return true
    end if
    
    n = m._gbhash("__" + namespace[0], userId, 1)
    if n = invalid then return false
    
    return n >= m._toDouble(namespace[1]) and n < m._toDouble(namespace[2])
end function

' ===================================================================
' Track feature usage (called on every feature evaluation)
' ===================================================================
sub GrowthBook__trackFeatureUsage(featureKey as string, result as object)
    ' Call the feature usage callback if set
    if m.onFeatureUsage <> invalid
        m.onFeatureUsage(featureKey, result)
    end if
    
    ' Notify tracking plugins
    m._notifyPlugins("featureUsage", { featureKey: featureKey, result: result })
end sub

' ===================================================================
' Notify tracking plugins of events
' ===================================================================
sub GrowthBook__notifyPlugins(eventType as string, data as object)
    for each plugin in m.trackingPlugins
        if eventType = "experimentViewed" and plugin.onExperimentViewed <> invalid
            plugin.onExperimentViewed(data.experiment, data.result)
        else if eventType = "featureUsage" and plugin.onFeatureUsage <> invalid
            plugin.onFeatureUsage(data.featureKey, data.result)
        end if
    end for
end sub

' ===================================================================
' Register a tracking plugin for event notifications
' ===================================================================
sub GrowthBook_registerTrackingPlugin(plugin as object)
    if type(plugin) = "roAssociativeArray"
        m.trackingPlugins.Push(plugin)
        ' Initialize plugin if it has an init method
        if plugin.init <> invalid
            plugin.init(m)
        end if
    end if
end sub

' ===================================================================
' Logging utility
' ===================================================================
sub GrowthBook__log(message as string)
    if m.enableDevMode
        print "[GrowthBook] " + message
    end if
end sub

' ===================================================================
' Hash attribute for testing (simplified version)
' ===================================================================
function GrowthBook__hashAttribute(value as string) as integer
    ' Simple hash for testing - returns 0-99
    hash = m._gbhash("", value, 1)
    if hash = invalid then return 0
    return Int(hash * 100)
end function

' ===================================================================
' Get Hash Context (helper for filters and experiments)
' Supports fallbackAttribute for sticky bucketing prerequisites
' ===================================================================
function GrowthBook__getHashContext(rule as object, featureKey as string) as object
    ' Get hash attribute (default to "id")
    ' Get hash value from attributes
    ' Get hash version (default to 1)
    ' Get seed (default to feature key)
    context = {
        hashAttribute: "id",
        hashValue: "",
        hashVersion: 1,
        seed: featureKey,
        success: false
    }
    
    if rule = invalid return context
    
    ' 1. Hash Attribute
    if rule.hashAttribute <> invalid and rule.hashAttribute <> ""
        context.hashAttribute = rule.hashAttribute
    end if
    
    ' 2. Hash Value - try primary attribute first
    val = m._getAttributeValue(context.hashAttribute)
    if val <> invalid
        if type(val) = "roString" or type(val) = "String"
            context.hashValue = val
        else
            context.hashValue = Str(val).Trim()
        end if
    end if
    
    ' 2b. FALLBACK - if primary value empty, try fallbackAttribute
    ' This is used for sticky bucketing when the primary hash attribute is not available
    if context.hashValue = "" and rule.fallbackAttribute <> invalid and rule.fallbackAttribute <> ""
        val = m._getAttributeValue(rule.fallbackAttribute)
        if val <> invalid
            if type(val) = "roString" or type(val) = "String"
                context.hashValue = val
            else
                context.hashValue = Str(val).Trim()
            end if
            ' Only update hashAttribute if we successfully got a fallback value
            if context.hashValue <> ""
                context.hashAttribute = rule.fallbackAttribute
            end if
        end if
    end if
    
    if context.hashValue = "" return context
    
    ' 3. Hash Version
    if rule.hashVersion <> invalid
        context.hashVersion = rule.hashVersion
    end if
    
    ' 4. Seed
    if rule.seed <> invalid and rule.seed <> ""
        context.seed = rule.seed
    else if rule.key <> invalid
        context.seed = rule.key
    end if
    
    context.success = true
    return context
end function

' ===================================================================
' Check if a rule is included based on filters/rollout
' ===================================================================
function GrowthBook__isRuleIncluded(rule as object, featureKey as string) as boolean
    ' If no hashing logic needed, it's included
    if rule.coverage = invalid and rule.range = invalid and rule.ranges = invalid and rule.filters = invalid and rule.namespace = invalid and (rule.hashVersion = invalid or rule.hashVersion = 1)
        return true
    end if
    
    context = m._getHashContext(rule, featureKey)
    if not context.success return false
    
    ' 1. Filters
    if rule.filters <> invalid
        for each filter in rule.filters
            filterSeed = featureKey
            if filter.seed <> invalid then filterSeed = filter.seed
            version = 2
            if filter.hashVersion <> invalid then version = filter.hashVersion
            
            ' Determine which attribute to use for this filter
            filterAttr = "id"
            if filter.attribute <> invalid and filter.attribute <> ""
                filterAttr = filter.attribute
            else if rule.hashAttribute <> invalid and rule.hashAttribute <> ""
                filterAttr = rule.hashAttribute
            end if
            
            filterVal = m._getAttributeValue(filterAttr)
            if filterVal = invalid then return false
            filterValStr = ""
            if type(filterVal) = "roString" or type(filterVal) = "String"
                filterValStr = filterVal
            else
                filterValStr = Str(filterVal).Trim()
            end if
            if filterValStr = "" return false
            
            n = m._gbhash(filterSeed, filterValStr, version)
            if n = invalid return false
            
            inAnyRange = false
            for each rng in filter.ranges
                if m._inRange(n, rng)
                    inAnyRange = true
                    exit for
                end if
            end for
            if not inAnyRange return false
        end for
        
        ' If filters matched, return true and IGNORE standard rollout/namespace
        return true
    end if
    
    ' 2. Standard Rollout/Range/Namespace (Only if no filters)
    if rule.namespace <> invalid
        if not m._inNamespace(context.hashValue, rule.namespace) return false
    end if
    
    if rule.range <> invalid
        n = m._gbhash(context.seed, context.hashValue, context.hashVersion)
        if n = invalid or not m._inRange(n, rule.range) return false
    else if rule.ranges <> invalid
        n = m._gbhash(context.seed, context.hashValue, context.hashVersion)
        inAnyRange = false
        for each rng in rule.ranges
            if n = invalid then exit for
            if m._inRange(n, rng)
                inAnyRange = true
                exit for
            end if
        end for
        if not inAnyRange return false
    else if rule.coverage <> invalid and rule.variations = invalid
        coverage# = m._toDouble(rule.coverage)
        n = m._gbhash(context.seed, context.hashValue, context.hashVersion)
        ' Half-open, like bucket ranges: a user whose hash equals the coverage is excluded
        if n = invalid or n >= coverage# return false
    end if
    
    return true
end function

' ===================================================================
' Utility Functions
' ===================================================================

function GrowthBook_toBoolean(value as dynamic) as boolean
    if value = invalid
        return false
    end if
    
    if type(value) = "roBoolean" or type(value) = "Boolean"
        return value
    end if
    
    if type(value) = "roString" or type(value) = "String"
        return value <> ""
    end if
    
    if type(value) = "roInteger" or type(value) = "Integer" or type(value) = "LongInteger"
        return value <> 0
    end if
    
    if type(value) = "roFloat" or type(value) = "Float" or type(value) = "Double"
        return value <> 0.0
    end if
    
    ' Other objects (AA, Array) are truthy
    return true
end function

' ===================================================================
' AES-128-CBC Decryption for Encrypted Feature Payloads
' Requires Roku OS 9.2+ for roEVPCipher support
' ===================================================================
function GrowthBook__decrypt(encryptedStr as string, keyStr as string) as string
    ' Validate inputs
    if encryptedStr = "" or keyStr = "" then return ""
    
    ' Format: "base64(iv).base64(ciphertext)"
    dotIndex = Instr(1, encryptedStr, ".")
    if dotIndex = 0 or dotIndex = 1 then return ""
    
    ivStr = Left(encryptedStr, dotIndex - 1)
    ctStr = Mid(encryptedStr, dotIndex + 1)
    if ivStr = "" or ctStr = "" then return ""
    
    ' Base64 decode all components
    keyBytes = CreateObject("roByteArray")
    ivBytes = CreateObject("roByteArray")
    ctBytes = CreateObject("roByteArray")
    
    ' Decode key - FromBase64String may silently fail on invalid input
    keyBytes.FromBase64String(keyStr)
    if keyBytes.Count() = 0
        m._log("ERROR: Invalid or empty base64 key")
        return ""
    end if
    
    ' Decode IV
    ivBytes.FromBase64String(ivStr)
    if ivBytes.Count() = 0
        m._log("ERROR: Invalid or empty base64 IV")
        return ""
    end if
    
    ' Decode ciphertext
    ctBytes.FromBase64String(ctStr)
    if ctBytes.Count() = 0
        m._log("ERROR: Invalid or empty base64 ciphertext")
        return ""
    end if
    
    ' Validate AES-128 requirements
    ' Key must be 16 bytes (128 bits)
    if keyBytes.Count() <> 16
        m._log("ERROR: Key must be 16 bytes for AES-128")
        return ""
    end if
    
    ' IV must be non-empty
    if ivBytes.Count() = 0
        m._log("ERROR: IV must be non-empty")
        return ""
    end if
    
    ' Ciphertext must be non-empty
    if ctBytes.Count() = 0
        m._log("ERROR: Invalid ciphertext length")
        return ""
    end if
    
    ' Create cipher (requires Roku OS 9.2+)
    cipher = m._createObject("roEVPCipher")
    if cipher = invalid
        m._log("ERROR: roEVPCipher not available (requires Roku OS 9.2+)")
        return ""
    end if
    
    try
        ' Setup: false=decrypt, aes-128-cbc algorithm, key, iv, padding=1 (PKCS7)
        if not cipher.Setup(false, "aes-128-cbc", keyBytes, ivBytes, 1)
            m._log("ERROR: Cipher setup failed")
            return ""
        end if
        
        ' Process the encrypted data
        decrypted = cipher.Update(ctBytes)
        if decrypted = invalid
            m._log("ERROR: Decryption failed")
            return ""
        end if
        
        ' Get final block (handles PKCS7 padding removal)
        finalBlock = cipher.Final()
        if finalBlock <> invalid and finalBlock.Count() > 0
            decrypted.Append(finalBlock)
        end if
        
        return decrypted.ToAsciiString()
    catch e
        m._log("ERROR: Cipher operation failed - " + e.message)
        return ""
    end try
end function

' ===================================================================
' GrowthBook Tracking Plugin - Built-in Data Warehouse Integration
' Batches experiment and feature events, sends via HTTP POST
' ===================================================================
function GrowthBookTrackingPlugin(config as object) as object
    instance = {
        ' Configuration
        ingestorHost: "",
        clientKey: "",
        batchSize: 10,
        
        ' State
        eventQueue: [],
        http: invalid,
        
        ' Methods
        init: GrowthBookTrackingPlugin_init,
        onExperimentViewed: GrowthBookTrackingPlugin_onExperimentViewed,
        onFeatureUsage: GrowthBookTrackingPlugin_onFeatureUsage,
        flush: GrowthBookTrackingPlugin_flush
    }
    
    if config.ingestorHost <> invalid then instance.ingestorHost = config.ingestorHost
    if config.clientKey <> invalid then instance.clientKey = config.clientKey
    if config.batchSize <> invalid then instance.batchSize = config.batchSize
    
    return instance
end function

sub GrowthBookTrackingPlugin_init(gb as object)
    if gb.http <> invalid
        m.http = gb.http
    else
        try
            m.http = CreateObject("roURLTransfer")
            m.http.SetCertificatesFile("common:/certs/ca-bundle.crt")
        catch e
            m.http = invalid
        end try
    end if
end sub

sub GrowthBookTrackingPlugin_onExperimentViewed(experiment as object, result as object)
    event = {
        event_type: "experiment_viewed",
        timestamp: CreateObject("roDateTime").AsSeconds(),
        experiment_id: experiment.key,
        variation_id: result.variationId
    }
    m.eventQueue.Push(event)
    
    if m.eventQueue.Count() >= m.batchSize
        m.flush()
    end if
end sub

sub GrowthBookTrackingPlugin_onFeatureUsage(featureKey as string, result as object)
    event = {
        event_type: "feature_evaluated",
        timestamp: CreateObject("roDateTime").AsSeconds(),
        feature_key: featureKey,
        value: result.value,
        source: result.source
    }
    m.eventQueue.Push(event)
    
    if m.eventQueue.Count() >= m.batchSize
        m.flush()
    end if
end sub

sub GrowthBookTrackingPlugin_flush()
    if m.eventQueue.Count() = 0 then return
    if m.http = invalid then return
    if m.ingestorHost = "" then return
    
    payload = FormatJson({
        events: m.eventQueue,
        clientKey: m.clientKey
    })
    
    m.http.SetUrl(m.ingestorHost + "/events")
    m.http.AsyncPostFromString(payload)
    
    m.eventQueue = []
end sub

' ===================================================================
' Sticky Bucket Logic
' ===================================================================

' Build the sticky bucket experiment key: "expKey__bucketVersion"
function GrowthBook__getStickyBucketExperimentKey(expKey as string, bucketVersion as integer) as string
    return expKey + "__" + Str(bucketVersion).Trim()
end function

' Look up sticky bucket variation from cached assignment docs
' Checks both hashAttribute (higher priority) and fallbackAttribute (lower priority)
' Returns { variation: integer, versionIsBlocked: boolean }
function GrowthBook__getStickyBucketVariation(rule as object, featureKey as string) as object
    result = { variation: -1, versionIsBlocked: false, source: "none" }
    
    if m.stickyBucketService = invalid then return result
    if rule.disableStickyBucketing = true then return result
    
    ' Determine the experiment key
    expKey = rule.key
    if expKey = invalid or expKey = "" then expKey = featureKey
    
    bucketVersion = 0
    if rule.bucketVersion <> invalid then bucketVersion = rule.bucketVersion
    minBucketVersion = 0
    if rule.minBucketVersion <> invalid then minBucketVersion = rule.minBucketVersion
    
    assignments = {}
    source = "none"
    
    ' 1. Check Primary (hashAttribute) first - HIGHER priority
    hashAttr = "id"
    if rule.hashAttribute <> invalid and rule.hashAttribute <> "" then hashAttr = rule.hashAttribute
    attrVal = m._getAttributeValue(hashAttr)
    if attrVal <> invalid
        valStr = ""
        if type(attrVal) = "roString" or type(attrVal) = "String" then valStr = attrVal else valStr = Str(attrVal).Trim()
        if valStr <> ""
            doc = m._stickyBucketAssignmentDocs[hashAttr + "||" + valStr]
            if doc <> invalid and doc.assignments <> invalid
                assignments = doc.assignments
                source = "primary"
            end if
        end if
    end if
    
    ' 2. Check Fallback if not found in primary
    currentKey = m._getStickyBucketExperimentKey(expKey, bucketVersion)
    foundInPrimary = assignments.DoesExist(currentKey)
    
    if rule.fallbackAttribute <> invalid and rule.fallbackAttribute <> ""
        attrVal = m._getAttributeValue(rule.fallbackAttribute)
        if attrVal <> invalid
            valStr = ""
            if type(attrVal) = "roString" or type(attrVal) = "String" then valStr = attrVal else valStr = Str(attrVal).Trim()
            if valStr <> ""
                doc = m._stickyBucketAssignmentDocs[rule.fallbackAttribute + "||" + valStr]
                if doc <> invalid and doc.assignments <> invalid
                    ' Merge every fallback assignment, preferring primary for the same key,
                    ' so an old bucket version stored under the fallback still blocks
                    for each k in doc.assignments
                        if not assignments.DoesExist(k) then assignments[k] = doc.assignments[k]
                    end for
                    if not foundInPrimary and doc.assignments.DoesExist(currentKey) then source = "fallback"
                end if
            end if
        end if
    end if
    
    if assignments.Count() = 0 then return result
    
    result.source = source
    
    ' Check for blocked versions (on the final merged assignments)
    for v = 0 to minBucketVersion - 1
        vKey = m._getStickyBucketExperimentKey(expKey, v)
        if assignments.DoesExist(vKey)
            result.versionIsBlocked = true
            return result
        end if
    end for
    
    ' Look for current version assignment
    if assignments.DoesExist(currentKey)
        variationKey = assignments[currentKey]
        found = false
        if rule.meta <> invalid
            for i = 0 to rule.meta.Count() - 1
                if rule.meta[i].key = variationKey
                    result.variation = i
                    found = true
                    exit for
                end if
            end for
        end if
        if not found then result.variation = Int(Val(variationKey))
    end if
    
    return result
end function

' Save sticky bucket assignment to both in-memory cache and service
' Saves under context.hashAttribute (the resolved attribute from _getHashContext)
sub GrowthBook__saveStickyBucketAssignment(rule as object, context as object, variationIndex as integer, featureKey as string)
    if m.stickyBucketService = invalid then return
    if rule.disableStickyBucketing = true then return
    
    expKey = rule.key
    if expKey = invalid or expKey = "" then expKey = featureKey
    
    bucketVersion = 0
    if rule.bucketVersion <> invalid then bucketVersion = rule.bucketVersion
    
    assignmentKey = m._getStickyBucketExperimentKey(expKey, bucketVersion)
    docKey = context.hashAttribute + "||" + context.hashValue
    newValue = Str(variationIndex).Trim()
    
    ' Get existing doc from cache or start fresh
    existing = m._stickyBucketAssignmentDocs[docKey]
    assignments = {}
    if existing <> invalid and existing.assignments <> invalid
        for each k in existing.assignments
            assignments[k] = existing.assignments[k]
        end for
    end if
    
    ' Skip save if assignment already matches
    if assignments.DoesExist(assignmentKey) and assignments[assignmentKey] = newValue
        return
    end if
    
    ' Add/update the assignment
    assignments[assignmentKey] = newValue
    
    ' Update in-memory cache
    m._stickyBucketAssignmentDocs[docKey] = {
        attributeName: context.hashAttribute,
        attributeValue: context.hashValue,
        assignments: assignments
    }
    
    ' Persist to service
    m.stickyBucketService.saveAssignments(context.hashAttribute, context.hashValue, assignments)
end sub

' ===================================================================
' Sticky Bucket Services
' ===================================================================

' In-memory sticky bucket service (for testing/simple use)
function GrowthBookInMemoryStickyBucketService() as object
    return {
        docs: {},
        getAssignments: function(attrName as string, attrValue as string) as object
            key = attrName + "||" + attrValue
            return m.docs[key]
        end function,
        saveAssignments: sub(attrName as string, attrValue as string, assignments as object)
            key = attrName + "||" + attrValue
            m.docs[key] = {
                attributeName: attrName,
                attributeValue: attrValue,
                assignments: assignments
            }
        end sub,
        getAllAssignments: function() as object
            return m.docs
        end function
    }
end function

' Registry-based persistent sticky bucket service (Roku OS 7.0+)
function GrowthBookRegistryStickyBucketService() as object
    return {
        section: CreateObject("roRegistrySection", "GrowthBookStickyBuckets"),
        getAssignments: function(attrName as string, attrValue as string) as object
            key = attrName + "||" + attrValue
            value = m.section.Read(key)
            if value <> "" then return ParseJson(value)
            return invalid
        end function,
        saveAssignments: sub(attrName as string, attrValue as string, assignments as object)
            key = attrName + "||" + attrValue
            doc = {
                attributeName: attrName,
                attributeValue: attrValue,
                assignments: assignments
            }
            m.section.Write(key, FormatJson(doc))
            m.section.Flush()
        end sub,
        getAllAssignments: function() as object
            result = {}
            keys = m.section.GetKeyList()
            for each key in keys
                value = m.section.Read(key)
                if value <> "" then result[key] = ParseJson(value)
            end for
            return result
        end function
    }
end function
