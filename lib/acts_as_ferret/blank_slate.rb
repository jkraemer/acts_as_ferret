module ActsAsFerret
  
  if defined?(ActiveSupport::BasicObject)
    # Rails 2.3, 3.x
    class BlankSlate < ActiveSupport::BasicObject
    end
    
  elsif defined?(::BasicObject)
    # Ruby 1.9.x
    class BlankSlate < BasicObject
    end
    
  elsif defined?(::BlankSlate)
    # former 2.x rails versions (?)
    class BlankSlate < ::BlankSlate
    end
    
  else
    # 'backported' for Rails pre 2.0
    #
    #--
    # Copyright 2004, 2006 by Jim Weirich (jim@weirichhouse.org).
    # All rights reserved.

    # Permission is granted for use, copying, modification, distribution,
    # and distribution of modified versions of this work as long as the
    # above copyright notice is included.
    #++

    ######################################################################
    # BlankSlate provides an abstract base class with no predefined
    # methods (except for <tt>\_\_send__</tt> and <tt>\_\_id__</tt>).
    # BlankSlate is useful as a base class when writing classes that
    # depend upon <tt>method_missing</tt> (e.g. dynamic proxies).
    #
    class BlankSlate
      class << self
        # Hide the method named +name+ in the BlankSlate class.  Don't
        # hide +instance_eval+ or any method beginning with "__".
        def hide(name)
          if instance_methods.include?(name.to_s) and name !~ /^(__|instance_eval|methods)/
            @hidden_methods ||= {}
            @hidden_methods[name.to_sym] = instance_method(name)
            undef_method name
          end
        end

      end

      instance_methods.each { |m| hide(m) }

    end

  end
end
