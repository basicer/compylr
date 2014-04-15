var helpers, _,
  __slice = [].slice;

_ = require('lodash');

helpers = require('./helpers');

module.exports = function(handlebars) {
  handlebars || (handlebars = require('handlebars'));
  handlebars.registerHelper("eachExpression", function(name, _in, expression, options) {
    var value;
    value = helpers.safeEvalStaticExpression(expression, this);
    return instance.helpers.forEach(name, _in, value, options);
  });
  handlebars.registerHelper("styleExpression", function(expression, options) {
    var key, out, val, value;
    value = helpers.safeEvalWithContext(expression, this, true);
    out = ';';
    for (key in value) {
      val = value[key];
      out += "" + (_.str.dasherize(key)) + ": " + val + ";";
    }
    return " " + out + " ";
  });
  handlebars.registerHelper("classExpression", function(expression, options) {
    var key, out, val, value;
    value = helpers.safeEvalWithContext(expression, this, true);
    out = [];
    for (key in value) {
      val = value[key];
      if (val) {
        out.push(key);
      }
    }
    return ' ' + out.join(' ') + ' ';
  });
  handlebars.registerHelper("ifExpression", function(expression, options) {
    var value;
    value = helpers.safeEvalStaticExpression(expression, this);
    if (!options.hash.includeZero && !value) {
      return options.inverse(this);
    } else {
      return options.fn(this);
    }
  });
  handlebars.registerHelper("expression", function(expression, options) {
    var value;
    value = helpers.safeEvalStaticExpression(expression, this);
    return value;
  });
  handlebars.registerHelper("hbsShow", function(expression, options) {
    var value;
    value = helpers.safeEvalStaticExpression(expression, this);
    if (value) {
      return ' data-hbs-show ';
    } else {
      return ' data-hbs-hide ';
    }
  });
  handlebars.registerHelper("hbsHide", function(expression, options) {
    var value;
    value = helpers.safeEvalStaticExpression(expression, this);
    if (value) {
      return ' data-hbs-hide ';
    } else {
      return ' data-hbs-show ';
    }
  });
  handlebars.registerHelper("json", function() {
    var args, obj, options, _i;
    args = 2 <= arguments.length ? __slice.call(arguments, 0, _i = arguments.length - 1) : (_i = 0, []), options = arguments[_i++];
    obj = args[0] || this;
    return new handlebars.SafeString(JSON.stringify(obj, null, 2));
  });
  handlebars.registerHelper("interpolatedScript", function(options) {
    var key, scriptStr, value, _ref;
    scriptStr = "<script";
    _ref = options.hash;
    for (key in _ref) {
      value = _ref[key];
      scriptStr += " " + key + "=\"" + value + "\"";
    }
    scriptStr += '>';
    return "" + scriptStr + " " + (options.fn(this)) + " </script>";
  });
  return handlebars.registerHelper("forEach", function(name, _in, contextExpression) {
    var context, ctx, data, fn, i, inverse, iterContext, iterCtx, j, key, nameSplit, objSize, options, ret, value;
    context = value = helpers.safeEvalStaticExpression(contextExpression, this);
    options = _.last(arguments);
    fn = options.fn;
    ctx = this;
    inverse = options.inverse;
    i = 0;
    ret = "";
    data = void 0;
    nameSplit = name.split(',');
    if (context && _.isObject(context)) {
      if (_.isArray(context) || _.isString(context)) {
        j = context.length;
        while (i < j) {
          iterContext = _.clone(ctx);
          iterContext[name] = context[i];
          if (data) {
            data[name + 'Index'] = i;
            data.$index = i;
            data.$first = i === 0;
            data.$last = i === (iterContext.length - 1);
            data.$odd = i % 2;
            data.$even = !(i % 2);
            data.$middle = !data.$first && !data.$last;
          }
          ret = ret + fn(iterContext, {
            data: data
          });
          i++;
        }
      } else {
        objSize = _.size(context);
        for (key in context) {
          value = context[key];
          if (context.hasOwnProperty(key)) {
            iterCtx = _.clone(ctx);
            iterCtx[name] = context[key];
            if (data) {
              data[nameSplit[0]] = key;
              data[nameSplit[1]] = value;
              data.$index = i;
              data.$first = i === 0;
              data.$odd = i % 2;
              data.$even = !(i % 2);
              data.$last = i === objSize - 1;
              data.$middle = !data.$first && !data.$last;
            }
            ret = ret + fn(iterCtx, {
              data: data
            });
            i++;
          }
        }
      }
    }
    return ret;
  });
};
