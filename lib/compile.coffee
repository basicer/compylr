#!/usr/bin/env coffee

argv         = require('optimist').argv
fs           = require 'fs'
_            = require 'lodash'
_str         = require 'underscore.string'
beautifyHtml = require('js-beautify').html
helpers      = require './helpers'
config       = require './config'
glob         = require 'glob'


# Helpers - - - - - - - - - - - - - - - - - - - - - - - - -

# E.g. <div ng-repeat="foo in bar"></div>
getRefNames = (str, options) ->
  tags = str.match(/<.*?>/g)
  map = {}
  return map unless tags
  tags.reverse()
  depth = 0
  for tag in tags
    if tag.indexOf('</')
      depth--
      return map if depth < 0
    else
      depth++
      repeat = tag.match /\sng-repeat="(.*?)"/g
      continue unless repeat
      repeatText = RegExp.$1
      split = repeatText.split ' in '
      # product: selectedProducts
      map[slit[0]] = split[1]
  map

stripComments = (str) ->
  str.replace(/<!--[\s\S]*?-->/g, '')

selfClosingTags = 'area, base, br, col, command, embed, hr, img, input,
  keygen, link, meta, param, source, track, wbr'.split /,\s*/

escapeCurlyBraces = (str) ->
  str
    .replace(/\{/g, '&#123;')
    .replace(/\}/g, '&#125;')

beautify = (str) ->
  str = str.replace /\{\{(#|\/)([\s\S]+?)\}\}/g, (match, type, body) ->
    modifier = if type is '#' then '' else '/'
    "<#{modifier}##{body}>"

  pretty = beautifyHtml str,
    indent_size: 2
    indent_inner_html: true
    preserve_newlines: false

  pretty = pretty
    .replace /<(\/?#)(.*)>/g, (match, modifier, body) ->
      modifier = '/' if modifier is '/#'
      "{{#{modifier}#{body}}}"

  pretty


# TODO: pretty format
#   replace '\n' with '\n  ' where '  ' is 2 spaces * depth
#   Maybe prettify at very end instead
getCloseTag = (string) ->
  string = string.trim()
  index = 0
  depth = 0
  open = string.match(/<.*?>/)[0]
  tagName = string.match(/<\w+/)[0].substring 1
  string = string.replace open, ''

  if tagName in selfClosingTags
    out =
      before: open
      after: string
    return out

  for char, index in string
    # Close tag
    if char is '<' and string[index + 1] is '/'
      if not depth
        after = string.substr index
        close = after.match(/<\/.*?>/)[0]
        afterWithTag = after + close
        afterWithoutTag = after.substring close.length

        return (
          after: afterWithoutTag
          before: open + '\n' + string.substr(0, index) + close
        )
      else
        depth--
    # Open tag
    else if char is '<'
      selfClosing = false
      tag = string.substr(index).match(/\w+/)[0]
      # Check if self closing tag
      if tag and tag in selfClosingTags
        continue
      depth++

# FIXME: this will break for pipes inside strings
processFilters = (str) ->
  filterSplit = str.match /[^\|]+/
  filters: filterSplit.slice(1).join ' | '
  replaced: filterSplit[0]

# FIXME: will breal if this is in words
escapeReplacement = (str) ->
  convertNgToDataNg str

convertNgToDataNg = (str) ->
  str.replace /\sng-/g, ' data-ng-'

convertDataNgToNg = (str) ->
  str.replace /\sdata-ng-/g, ' ng-'

unescapeReplacements = (str) ->
  str
  # str.replace /__NG__/g, 'ng-'

escapeBasicAttribute = (str) ->
  '__ATTR__' + str + '__ATTR__'

unescapeBasicAttributes = (str) ->
  str.replace /__ATTR__/g, ''

escapeBraces = (str) ->
  str
    .replace(/\{\{/g, '__{{__')
    .replace(/\}\}/g, '__}}__')

unescapeBraces = (str) ->
  str
    .replace(/__\{\{__/g, '{{')
    .replace(/__\}\}__/g, '}}')


# Compile - - - - - - - - - - - - - - - - - - - - - - - -

compile = (options) ->
  filePath = argv.file or options.file
  if filePath
    helpers.logVerbose 'filePath', filePath
    file = fs.readFileSync filePath, 'utf8'
  else
    file = options.string or options

  updated = true
  interpolated = stripComments file
  i = 0
  maxIters = 10000

  while updated
    updated = false
    firstLoop = false

    throw new Error 'infinite update loop' if i++ > maxIters

    interpolated = interpolated

      # ng-repeat - - - - - - - - - - - - - -

      .replace(/<[^>]*?\sng-repeat="(.*?)".*?>([\S\s]+)/gi, (match, text, post) ->
        helpers.logVerbose 'match 1'
        updated = true
        varName = text
        varNameSplit = varName.split ' '
        varNameSplit[0] = "'#{varNameSplit[0]}'"
        varName = varNameSplit.join ' '
        processedFilters = processFilters varName
        varName = processedFilters.replaced
        filters = processedFilters.filters
        # varName = text.split(' in ')[1]
        close = getCloseTag match
        filterStr = if filters.trim() then " filters=\"#{filters}\"" else ''
        if close
          "{{#forEach #{varName}#{filterStr}}}\n#{close.before.replace /\sng-repeat/, ' data-ng-repeat'}\n{{/forEach}}\n#{close.after}"
        else
          throw new Error 'Parse error! Could not find close tag for ng-repeat'
      )

      # ng-if - - - - - - - - - - - - - - - - -

      .replace(/<[^>]*?\sng-if="(.*?)".*?>([\S\s]+)/, (match, varName, post) ->
        helpers.logVerbose 'match 2'
        updated = true
        varName = varName.trim()
        # TODO: expressions
        tagName = if varName.split(' ')[1] then 'ifExpression' else 'if'
        if varName.indexOf('!') is 0 and tagName is 'if'
          tagName = 'unless'
          varName = varName.substr 1
        else if tagName is 'ifExpression'
          varName = "\"#{varName}\""

        close = getCloseTag match
        if close
          "{{##{tagName} #{varName}}}\n#{close.before.replace /\sng-if=/, " data-ng-if="}\n{{/#{tagName}}}\n#{close.after}"
        else
          throw new Error 'Parse error! Could not find close tag for ng-if\n\n' + match + '\n\n' + file
      )

      # ng-include - - - - - - - - - - - - - -

      .replace(/<[^>]*?\sng-include="'(.*)'".*?>/, (match, includePath, post) ->
        helpers.logVerbose 'match 3'
        updated = true
        includePath = includePath.replace '.tpl.html', ''
        match = match.replace /\sng-include=/, ' data-ng-include='
        "#{match}\n{{> #{includePath}}}"
      )

      # ng-src, ng-href, ng-value - - - - - - -

      .replace(/\s(ng-src|ng-href|ng-value)="(.*)"/, (match, attrName, attrVal) ->
        helpers.logVerbose 'match 4'
        updated = true
        escapedMatch = escapeCurlyBraces match
        escapedAttrVal = escapeBraces attrVal
        """#{escapedMatch.replace ' ' + attrName, ' data-' + attrName} #{attrName.substring(3)}="#{escapedAttrVal}" """
      )

      # ng-class, ng-style - - - - - - - - - -

      .replace(/<(\w+)[^>]*\s(ng-class|ng-style)\s*=\s*"([^>"]+)"[\s\S]*?>/, (match, tagName, attrName, attrVal) ->
        helpers.logVerbose 'match 8', tagName: tagName, attrName: attrName, attrVal: attrVal
        updated = true
        type = attrName.substr 3 # 'class' or 'style'
        typeMatch = match.match new RegExp "\\s#{type}=\"([\\s\\S]*?)\""
        typeStr = typeMatch and typeMatch[0].substr(1) or "#{type}=\"\""
        typeStrOpen = typeStr.substr 0, typeStr.length - 1
        typeExpressionStr = """{{#{type}Expression "#{attrVal}"}}"""
        if typeMatch
          match = match.replace typeMatch, ''
        match = match.replace new RegExp("\\sng-#{type}"), "data-ng-#{type}"

        match.replace "<#{tagName}", """<#{tagName} #{typeStrOpen} #{typeExpressionStr}" """
      )

      # click-action - - - - - - - - - - - - - - -

      # TODO: ng-click only on anchors
      .replace(/<(\w+)[^>]*(\sclick-action\s*=\s*)"([^>"]+)"[\s\S]*/, (match, tagName, attrName, attrVal) ->
        helpers.logVerbose 'match 7', attrName: attrName, attrVal: attrVal
        updated = true
        hrefStr = """href="{{urlPath}}?action=#{encodeURIComponent attrVal}" """
        anchorStr = escapeBraces """<a #{hrefStr} data-ng-#{escapeCurlyBraces hrefStr}"""

        index = interpolated.indexOf match
        beforeStr = interpolated.substr 0, index
        refs = getRefNames beforeStr
        # FIXME: will break for things like 'product' and 'products'
        for key, value of refs
          # E.g. ng-click="activeProduct = product" -> ng-click="activeProduct = products[{{@activeProductIndex}}]"
          attrVal = attrVal.replace key, "#{value}[{{@#{key}Index}}]"

        if tagName is 'a'
          # TODO: preserve other url query params - keep a hash in data and add to url
          match.replace("<a", anchorStr).replace attrName, escapeBasicAttribute attrName
        else
          close = getCloseTag match
          "#{anchorStr}>\n#{close.before.replace attrName, escapeBasicAttribute attrName}\n</a>\n#{close.after}"
      )

      # attr="{{intrerpolation}}" - - - - - - - -

      .replace(/<[^>]*?([\w\-]+)\s*=\s*"([^">_]*?\{\{[^">]+\}\}[^">_]*?)".*?>/, (match, attrName, attrVal) ->
        helpers.logVerbose 'match 5', attrName: attrName, attrVal: attrVal
        # Match without the final '#'
        trimmedMatch = match.substr 0, match.length - 1
        trimmedMatch = trimmedMatch.replace "#{attrName}=", escapeBasicAttribute "#{attrName}="
        if attrName.indexOf('data-ng-attr-') is 0 or _.contains attrVal, '__{{__'
          match
        else
          updated = true
          newAttrVal = attrVal.replace /\{\{([\s\S]+?)\}\}/g, (match, expression) ->
            match = match.trim()
            if expression.length isnt expression.match(/[\w\.]+/)[0].length
              "{{expression '#{expression.replace /'/g, "\\'"}'}}"
            else
              match

          trimmedMatch = trimmedMatch.replace attrVal, escapeBraces newAttrVal
          """#{trimmedMatch} data-ng-attr-#{attrName}="#{escapeCurlyBraces attrVal}">"""
      )

      # ng-show, ng-hide - - - - - - - - - - - - -

      .replace(/\s(ng-show|ng-hide)\s*=\s*"([^"]+)"/g, (match, showOrHide, expression) ->
        updated = true
        hbsTagType = if showOrHide is 'ng-show' then 'hbsShow' else 'hbsHide'
        match = match.replace ' ' + showOrHide, " data-#{showOrHide}"
        "#{match} {{#{hbsTagType} \"#{expression}\"}}"
      )

  i = 0
  updated = true
  while updated
    updated = false

    throw new Error 'infinite update loop' if i++ > maxIters

    interpolated = interpolated

      # {{interpolation}}, {{exression == true}} -

      .replace(/\{\{([^#\/>_][\s\S]*?[^_])\}\}/g, (match, body) ->
        helpers.logVerbose 'match 7'
        updated = true
        body = body.trim()
        words = body.match /[\w\.]+/
        isHelper = words[0] in ['json', 'expression', 'hbsShow', 'hbsHide', 'classExpression', 'styleExpression']
        if not isHelper
          prefix = ''
          suffix = ''
          if words and words[0].length isnt body.length
            helpers.logVerbose 'body', body
            prefix = 'expression "'
            suffix = '"'
          escapeBraces """<span data-ng-bind="#{body}">{{#{prefix}#{body}#{suffix}}}</span>"""
        else
          escapeBraces match
      )

  # Unescape and output - - - - - - - - - - - - - - - - - - - - - -

  interpolated = unescapeReplacements interpolated
  interpolated = unescapeBraces interpolated
  interpolated = unescapeBasicAttributes interpolated
  # interpolated = convertNgToDataNg interpolated
  interpolated = convertDataNgToNg interpolated
  beautified = beautify interpolated

  if argv.file and not argv['no-write']
    fs.writeFileSync 'template-output/output.html', beautified

  beautified

module.exports = compile