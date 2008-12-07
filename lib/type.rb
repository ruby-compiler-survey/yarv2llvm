#!/bin/ruby 
#
#  Type information class of Ruby or llvm
#

module YARV2LLVM
  include LLVM

class RubyType
  include LLVM
  include RubyHelpers

  @@type_table = []

  def initialize(type, lno = nil, name = nil, klass = nil)
    @name = name
    @line_no = lno
    if type == nil 
      @type = nil
    elsif type.is_a?(ComplexType) then
      @type = type
    else
      @type = PrimitiveType.new(type)
    end
    if klass then
      @klass = klass.name.to_sym
    else
      @klass = nil
    end
    @resolveed = false
    @same_type = []
    @same_value = []
    @@type_table.push self
  end
  attr_accessor :type
  attr_accessor :klass

  def dup_type
#    no = self.class.new(nil)
#    add_same_type(no)
#    no.add_same_type(no)
#    no
    self
  end

  def inspect2
    if @type then
      @type.inspect2
    else
      'nil'
    end
  end

  attr_accessor :type
  attr_accessor :resolveed
  attr :name
  attr :line_no

  def add_same_type(fty)
    @same_type.push fty
    # Complex type -> element type is same also.
    if type.is_a?(ComplexType) and fty.type.is_a?(ComplexType) then
      type.element_type.add_same_type(fty.type.element_type)
    end
  end

  def add_same_value(fty)
    @same_value.push fty
    # Complex type -> element type is same also.
    if type.is_a?(ComplexType) and fty.type.is_a?(ComplexType) then
      type.element_type.add_same_value(fty.type.element_type)
    end
  end
  
  def clear_same
    @same_type = []
    @same_value = []
  end

  def self.clear_content
    @@type_table.each do |ty|
      if ty.type then
        ty.type.content = nil
        if ty.type.is_a?(ArrayType) then
          ty.type.ptr = nil
          ty.type.element_content = {}
        end
      end
    end
  end

  def self.resolve
    @@type_table.each do |ty|
      ty.resolveed = false
    end

    @@type_table.each do |ty|
      ty.resolve
    end

#    @@type_table.each do |ty|
#      ty.clear_same
#    end
  end

  def resolve
    rone = lambda {|dupp|
      lambda {|ty|
        if ty.type and ty.type.is_a?(ComplexType) then
          if ty.type.is_a?(@type.class) and ty.type.class != @type.class then
            if dupp then
              @type = ty.type.dup_type
              @klass = ty.klass
            else
              @type = ty.type
              @klass = ty.klass
            end
            @resolveed = false
            resolve
            return
          end
          
          if @type.is_a?(ty.type.class) then
            if ty.type != @type then
              if dupp then
                ty.type = @type.dup_type
                ty.klass = klass
              else
                ty.type = @type
                ty.klass = klass
              end
            end
            ty.resolve
            next
          end
        end
        
        if ty.type and ty.type.llvm != @type.llvm then
          mess = "Type conflict \n"
          mess += "  #{ty.name}(#{ty.type.inspect2}) defined in #{ty.line_no} \n"
          mess += "  #{@name}(#{@type.inspect2}) define in #{@line_no} \n"
          raise mess
        elsif ty.type then
#          if dupp then
#            ty.type = @type.dup_type
#          end
        else
          if dupp then
            ty.type = @type.dup_type
            ty.klass = klass
          else
            ty.type = @type
            ty.klass = klass
          end
          ty.resolve
        end
      }
    }

    if @resolveed then
      return
    end

    if @type then
      @resolveed = true
      rone_dup = rone.call(true)
      @same_type.each(&rone_dup)
      rone_nodup = rone.call(false)
      @same_value.each(&rone_nodup)
    end
  end

  def self.fixnum(lno = nil, name = nil, klass = Fixnum)
    RubyType.new(Type::Int32Ty, lno, name, klass)
  end

  def self.float(lno = nil, name = nil, klass = Float)
    RubyType.new(Type::DoubleTy, lno, name, klass)
  end

  def self.string(lno = nil, name = nil, klass = String)
    RubyType.new(StringType.new, lno, name, klass)
  end

  def self.array(lno = nil, name = nil)
    etype = nil
    if name then
      etype = RubyType.typeof(name[0], lno, name[0])
    else
      etype = RubyType.new(nil)
    end
    na = ArrayType.new(nil)
    na.element_type = etype
    RubyType.new(na, lno, name, Array)
  end

  def self.symbol(lno = nil, name = nil, klass = Symbol)
    RubyType.new(VALUE, lno, name, klass)
  end

  def self.value(lno = nil, name = nil, klass = Object)
    RubyType.new(VALUE, lno, name, klass)
  end

  def self.from_sym(sym, lno, name)
    case sym
    when :Fixnum
      RubyType.fixnum(lno, name)

    when :Float
      RubyType.float(lno, name)

    when :String
      RubyType.string(lno, name)

    when :Symbol
      RubyType.symbol(lno, name)

    when :Array
      RubyType.array(lno, name)

    else
      RubyType.value(lno, name, Object)
    end
  end

  def self.typeof(obj, lno = nil, name = nil)
    case obj
    when ::Fixnum
      RubyType.fixnum(lno, name)

    when ::Float
      RubyType.float(lno, name)

    when ::String
      RubyType.string(lno, obj)

    when ::Symbol
      RubyType.symbol(lno, obj)

    when ::Array
      RubyType.array(lno, obj)

    when ::Class
      RubyType.value(lno, obj, obj)

    when ::Module
      RubyType.value(lno, obj, obj)

    else
      RubyType.value(lno, obj, obj.class)
    end
  end
end

class PrimitiveType
  include LLVM
  include RubyHelpers

  def initialize(type)
    @type = type
    @content = nil
  end
  attr_accessor :content

  def dup_type
    self.class.new(@type)
  end

  TYPE_HANDLER = {
    Type::Int32Ty =>
      {:inspect => "Int32Ty",

       :to_value => lambda {|val, b, context|
         x = b.shl(val, 1.llvm)
         b.or(FIXNUM_FLAG, x)
       },

       :from_value => lambda {|val, b, context|
         x = b.lshr(val, 1.llvm)
       },
      },

    Type::Int8Ty =>
      {:inspect => "Char",

       :to_value => lambda {|val, b, context|
         val32 = b.zext(val, Type::Int32Ty)
         x = b.shl(val32, 1.llvm)
         b.or(FIXNUM_FLAG, x)
       },

       :from_value => lambda {|val, b, context|
         val32 = b.zext(val, Type::Int32Ty)
         x = b.lshr(val32, 1.llvm)
       },
      },

    Type::DoubleTy =>
      {:inspect => "DoubleTy",

       :to_value => lambda {|val, b, context|
        atype = [Type::DoubleTy]
        ftype = Type.function(VALUE, atype)
        func = context.builder.external_function('rb_float_new', ftype)
        b.call(func, val)
       },

       :from_value => lambda {|val, b, context|
        val_ptr = b.int_to_ptr(val, P_RFLOAT)
        dp = b.struct_gep(val_ptr, 1)
        b.load(dp)
       },
      },

    VALUE =>
      {:inspect => "VALUE",

       :to_value => lambda {|val, b, context|
        val
       },

       :from_value => lambda {|val, b, context|
        val
       },
      },

    P_CHAR =>
      {:inspect => "P_CHAR",

       :to_value => lambda {|val, b, context|
        raise "Illigal convert P_CHAR to VALUE"
       },

       :from_value => lambda {|val, b, context|
        raise "Illigal convert VALUE to P_CHAR"
       },
      },
  }

  def to_value(val, b, context)
    TYPE_HANDLER[@type][:to_value].call(val, b, context)
  end

  def from_value(val, b, context)
    TYPE_HANDLER[@type][:from_value].call(val, b, context)
  end

  def inspect2
    if rc = TYPE_HANDLER[@type] then
      rc[:inspect]
    else
      self.inspect
    end
  end

  def llvm
    @type
  end
end

class ComplexType
  def dup_type
    self.class.new
  end
end

class AbstructContainerType<ComplexType
  include LLVM
  include RubyHelpers

  def initialize(etype)
    @element_type = RubyType.new(etype)
    @content = nil
  end
  attr_accessor :element_type
  attr_accessor :content

  def dup_type
    no = self.class.new(nil)
    no.element_type = @element_type
    no
  end

  def llvm
    VALUE
  end

  def inspect2
    "Abstruct Contanor type of #{@element_type.inspect2}"
  end
end

class ArrayType<AbstructContainerType
  include LLVM
  include RubyHelpers

  def initialize(etype)
    @element_type = RubyType.new(etype, nil, nil)
    @ptr = nil
    @element_content = Hash.new
  end
  attr_accessor :element_type
  attr_accessor :ptr
  attr_accessor :element_content

  def dup_type
    no = self.class.new(nil)
    no.element_type = @element_type
    no
  end

  def inspect2
    if @element_type then
      "Array of #{@element_type.inspect2}"
    else
      "Array of nil"
    end
  end

  def to_value(val, b, context)
    val
  end

  def from_value(val, b, context)
    val
  end

  def llvm
    VALUE
  end
end

class StringType<AbstructContainerType
  include LLVM
  include RubyHelpers

  def initialize
    @element_type = RubyType.new(CHAR, nil, nil, Fixnum)
  end
  attr :element_type

  def dup_type
    no = self.class.new
    no
  end

  def inspect2
    "String"
  end

  def to_value(val, b, context)
    ftype = Type.function(VALUE, [P_CHAR])
    func = context.builder.external_function('rb_str_new_cstr', ftype)
    b.call(func, val)
  end

  def from_value(val, b, context)
    ftype = Type.function(P_CHAR, [P_VALUE])
    func = context.builder.external_function('rb_string_value_ptr', ftype)
    strp = b.alloca(VALUE, 1)
    b.store(val, strp)
    b.call(func, strp)
  end

  def llvm
    P_CHAR
  end
end
end

