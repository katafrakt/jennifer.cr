module Jennifer
  module Model
    module RelationDefinition
      protected def __refresh_relation_retrieves
      end

      def append_relation(name : String, hash)
        raise Jennifer::UnknownRelation.new(self.class, name)
      end

      def relation_retrieved(name : String)
        raise Jennifer::UnknownRelation.new(self.class, name)
      end

      abstract def set_inverse_of(name : String, object)
      abstract def get_relation(name : String)

      # :nodoc:
      macro nullify_dependency(name, relation_type, polymorphic)
        # :nodoc:
        def __nullify_callback_{{name.id}}
          rel = self.class.{{name.id}}_relation
          options = {rel.foreign_field => nil}
          {% if polymorphic %} options[rel.foreign_type] = nil {% end %}
          {{name.id}}_query.update(options)
        end

        before_destroy :__nullify_callback_{{name.id}}
      end

      # :nodoc:
      macro delete_dependency(name, relation_type, polymorphic)
        # :nodoc:
        def __delete_callback_{{name.id}}
          {{name.id}}_query.delete
        end

        before_destroy :__delete_callback_{{name.id}}
      end

      # :nodoc:
      # TODO: add validation for cyclic destroy dependency
      macro destroy_dependency(name, relation_type, polymorphic)
        # :nodoc:
        def __destroy_callback_{{name.id}}
          {% if polymorphic && relation_type.id.stringify == "belongs_to" %}
            self.class.{{name.id}}_relation.destroy(self)
          {% else %}
            {{name.id}}_query.destroy
          {% end %}
        end

        before_destroy :__destroy_callback_{{name.id}}
      end

      # :nodoc:
      macro restrict_with_exception_dependency(name, relation_type, polymorphic)
        # :nodoc:
        def __restrict_with_exception_callback_{{name.id}}
          raise ::Jennifer::RecordExists.new(self, {{name.id.stringify}}) if {{name.id}}_query.exists?
        end

        before_destroy :__restrict_with_exception_callback_{{name.id}}
      end

      # :nodoc:
      macro declare_dependent(name, type, relation_type, polymorphic = false)
        {% type = type.id.stringify %}
        {% if relation_type == :belongs_to && type == "nullify" %}
          {% raise "Relation \"#{name}\" can't has belongs_to relation with dependent nullify" %}
        {% end %}
        {% if type == "nullify" %}
          ::Jennifer::Model::RelationDefinition.nullify_dependency({{name}}, {{relation_type}}, {{polymorphic}})
        {% elsif type == "delete" %}
          ::Jennifer::Model::RelationDefinition.delete_dependency({{name}}, {{relation_type}}, {{polymorphic}})
        {% elsif type == "destroy" %}
          ::Jennifer::Model::RelationDefinition.destroy_dependency({{name}}, {{relation_type}}, {{polymorphic}})
        {% elsif type == "restrict_with_exception" %}
          ::Jennifer::Model::RelationDefinition.restrict_with_exception_dependency({{name}}, {{relation_type}}, {{polymorphic}})
        {% elsif type == "none" %}
        {% else %}
          {% raise "Dependency type #{type} for relation #{name} of #{@type} is not allowed." %}
        {% end %}
      end

      # Specifies a one-to-many association.
      macro has_many(name, klass, request = nil, foreign = nil, foreign_type = nil, primary = nil, dependent = :nullify, inverse_of = nil, polymorphic = false)
        {{"{% RELATION_NAMES << #{name.id.stringify} %}".id}}
        ::Jennifer::Model::RelationDefinition.declare_dependent({{name}}, {{dependent}}, :has_many, {{polymorphic}})

        RELATIONS["{{name.id}}"] =
          {% if polymorphic %}
            {% relation_class = "::Jennifer::Relation::PolymorphicHasMany(#{klass}, #{@type})".id %}
            {% if inverse_of.nil? %} {% raise "`inverse_of` is required for a polymorphic has_many relation." %} {% end %}
            {{relation_class}}.new("{{name.id}}", {{foreign}}, {{primary}},
              {{klass}}.all{% if request %}.exec {{request}} {% end %}, foreign_type: {{foreign_type}}, inverse_of: {{inverse_of}})
          {% else %}
            {% relation_class = "::Jennifer::Relation::HasMany(#{klass}, #{@type})".id %}
            {{relation_class}}.new("{{name.id}}", {{foreign}}, {{primary}},
            {{klass}}.all{% if request %}.exec {{request}} {% end %})
          {% end %}
        @{{name.id}} = [] of {{klass}}
        @__{{name.id}}_retrieved = false

        # :nodoc:
        private def set_{{name.id}}_relation(collection : Array)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = collection
          {% if inverse_of %} collection.each(&.append_{{inverse_of.id}}(self)) {% end %}
        end

        private def set_{{name.id}}_relation(object)
          @__{{name.id}}_retrieved = true
          @{{name.id}} << object
          {% if inverse_of %} object.append_{{inverse_of.id}}(self) {% end %}
        end

        # Returns {{name.id}} relation metaobject
        def self.{{name.id}}_relation
          RELATIONS["{{name.id}}"].as({{relation_class}})
        end

        # Returns {{name.id}} relation query for the object
        def {{name.id}}_query
          primary_value = {{ primary ? primary.id : "primary".id }}
          {{@type}}.{{name.id}}_relation.query(primary_value).as(::Jennifer::QueryBuilder::ModelQuery({{klass}}))
        end

        # Returns array of related objects
        def {{name.id}}
          if !@__{{name.id}}_retrieved && @{{name.id}}.empty? && !new_record?
            set_{{name.id}}_relation({{name.id}}_query.to_a.as(Array({{klass}})))
          end
          @{{name.id}}
        end

        # Builds related object from hash and adds to relation
        def append_{{name.id}}(rel : Hash)
          obj = {{klass}}.build(rel, false)
          set_{{name.id}}_relation(obj)
          obj
        end

        def append_{{name.id}}(rel : {{klass}})
          set_{{name.id}}_relation(rel)
          rel
        end

        def append_{{name.id}}(rel : Jennifer::Model::Resource)
          obj = rel.as({{klass}})
          set_{{name.id}}_relation(obj)
          obj
        end

        # Removes given object from relation array
        def remove_{{name.id}}(rel : {{klass}})
          index = @{{name.id}}.index { |e| e.primary == rel.primary }
          if index
            {{@type}}.{{name.id}}_relation.remove(self, rel)
            @{{name.id}}.delete_at(index)
          end
          rel
        end

        # Insert given object to db and relation; doesn't support `inverse_of` option
        def add_{{name.id}}(rel : Hash)
          @{{name.id}} << {{@type}}.{{name.id}}_relation.insert(self, rel).as({{klass}})
        end

        def add_{{name.id}}(rel : {{klass}})
          @{{name.id}} << {{@type}}.{{name.id}}_relation.insert(self, rel)
        end

        def {{name.id}}_reload
          @{{name.id}} = {{name.id}}_query.to_a.as(Array({{klass}}))
        end
      end

      # Specifies a many-to-many relationship with another class. This associates two classes via an intermediate join table.
      # Unless the join table is explicitly specified as an option, it is guessed using the lexical order of the class names.
      # So a join between Developer and Project will give the default join table name of "developers_projects" because "D" precedes "P" alphabetically.
      # Note that this precedence is calculated using the < operator for String. This means that if the strings are of different lengths, and
      # the strings are equal when compared up to the shortest length, then the longer string is considered of higher lexical precedence than the shorter one.
      macro has_and_belongs_to_many(name, klass, request = nil, foreign = nil, primary = nil, join_table = nil, association_foreign = nil)
        {{"{% RELATION_NAMES << #{name.id.stringify} %}".id}}
        RELATIONS["{{name.id}}"] =
          ::Jennifer::Relation::ManyToMany({{klass}}, {{@type}}).new("{{name.id}}", {{foreign}}, {{primary}},
            {{klass}}.all{% if request %}.exec {{request}} {% end %}, {{join_table}}, {{association_foreign}})

        before_destroy :__{{name.id}}_clean

        # :nodoc:
        def __{{name.id}}_clean
          relation = self.class.{{name.id}}_relation
          this = self
          self.class.adapter.delete(::Jennifer::QueryBuilder::Query.new(relation.join_table!).where do
            c(relation.foreign_field) == this.attribute(relation.primary_field)
          end)
        end

        @{{name.id}} = [] of {{klass}}
        @__{{name.id}}_retrieved = false

        private def set_{{name.id}}_relation(object : Array)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = object
        end

        private def set_{{name.id}}_relation(object)
          @__{{name.id}}_retrieved = true
          @{{name.id}} << object
        end

        def self.{{name.id}}_relation
          RELATIONS["{{name.id}}"].as(::Jennifer::Relation::ManyToMany({{klass}}, {{@type}}))
        end

        def {{name.id}}_query
          primary_field = {% if primary %} {{primary.id}} {% else %} primary {% end %}
          RELATIONS["{{name.id}}"].query(primary_field).as(::Jennifer::QueryBuilder::ModelQuery({{klass}}))
        end

        def {{name.id}}
          if !@__{{name.id}}_retrieved && @{{name.id}}.empty? && !new_record?
            set_{{name.id}}_relation({{name.id}}_query.to_a.as(Array({{klass}})))
          end
          @{{name.id}}
        end

        def append_{{name.id}}(rel : Hash)
          obj = {{klass}}.build(rel, false)
          set_{{name.id}}_relation(obj)
          obj
        end

        def append_{{name.id}}(rel : {{klass}})
          set_{{name.id}}_relation(rel)
          rel
        end

        def append_{{name.id}}(rel : Jennifer::Model::Resource)
          set_{{name.id}}_relation(rel.as({{klass}}))
          rel
        end

        def remove_{{name.id}}(rel : {{klass}})
          index = @{{name.id}}.index { |e| e.primary == rel.primary }
          if index
            {{@type}}.{{name.id}}_relation.remove(self, rel)
            @{{name.id}}.delete_at(index)
          end
          rel
        end

        def add_{{name.id}}(rel : Hash)
          @{{name.id}} << {{@type}}.{{name.id}}_relation.insert(self, rel)
        end

        def add_{{name.id}}(rel : {{klass}})
          @{{name.id}} << {{@type}}.{{name.id}}_relation.insert(self, rel)
        end

        def {{name.id}}_reload
          @{{name.id}} = {{name.id}}_query.to_a.as(Array({{klass}}))
        end
      end

      # Specifies a one-to-one polymorphic association with another class. This macro should only be used if this class contains the foreign key.
      # If the other class contains the foreign key, then you should use has_one instead.
      macro polymorphic_belongs_to(name, klass, foreign = nil, foreign_type = nil, primary = nil,  dependent = :none)
        {{"{% RELATION_NAMES << #{name.id.stringify} %}".id}}
        {% relation_class = "#{name.id.camelcase}Relation".id %}
        ::Jennifer::Model::RelationDefinition.declare_dependent({{name}}, {{dependent}}, :belongs_to, true)

        ::Jennifer::Relation::IPolymorphicBelongsTo.define_relation_class({{name}}, {{@type}}, {{klass}}, {{klass.type_vars[0].types}})

        RELATIONS["{{name.id}}"] =
          {{relation_class}}.new("{{name.id}}", {{foreign}}, {{foreign_type}}, {{primary}})

        @{{name.id}} : {{klass}}?
        @__{{name.id}}_retrieved = false

        def self.{{name.id}}_relation
          RELATIONS["{{name.id}}"].as({{relation_class}})
        end

        def {{name.id}}
          if !@__{{name.id}}_retrieved && @{{name.id}}.nil? && !new_record?
            @__{{name.id}}_retrieved = true
            @{{name.id}} = {{name.id}}_reload
          end
          @{{name.id}}
        end

        {% for type in klass.type_vars[0].types %}
          {% related_name = type.id.split("::")[-1].underscore.id %}
          def {{name.id}}_{{related_name}}
            {{name.id}}.as({{type}})
          end

          def {{name.id}}_{{related_name}}?
            {{name.id}}.is_a?({{type}})
          end
        {% end %}

        def {{name.id}}!
          {{name.id}}.not_nil!
        end

        def {{name.id}}_query
          foreign_field = {{ (foreign ? foreign : "#{name.id}_id").id }}
          polymorphic_type = {{ (foreign_type ? foreign_type : "#{name.id}_type").id }}

          self.class.{{name.id}}_relation.query(foreign_field, polymorphic_type)
        end

        def {{name.id}}_reload
          foreign_field = {{ (foreign ? foreign : "#{name.id}_id").id }}
          polymorphic_type = {{ (foreign_type ? foreign_type : "#{name.id}_type").id }}

          @{{name.id}} = self.class.{{name.id}}_relation.load(foreign_field, polymorphic_type)
        end

        def append_{{name.id}}(rel : Hash)
          raise ::Jennifer::BaseException.new("Polymorphic relation can't be loaded dynamically.")
        end

        def append_{{name.id}}(rel : {{klass}})
          @__{{name.id}}_retrieved = true
          @{{name.id}} = rel
        end

        def append_{{name.id}}(rel : Jennifer::Model::Resource)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = rel.as({{klass}})
        end

        def remove_{{name.id}}
          {{@type}}.{{name.id}}_relation.remove(self)
          @{{name.id}} = nil
        end

        def add_{{name.id}}(rel : Hash)
          @{{name.id}} = {{@type}}.{{name.id}}_relation.insert(self, rel)
        end

        def add_{{name.id}}(rel : {{klass}})
          @{{name.id}} = {{@type}}.{{name.id}}_relation.insert(self, rel)
        end
      end

      # Specifies a one-to-one association with another class. This macro should only be used if this class contains the foreign key.
      # If the other class contains the foreign key, then you should use has_one instead.
      macro belongs_to(name, klass, request = nil, foreign = nil, primary = nil, dependent = :none)
        {{"{% RELATION_NAMES << #{name.id.stringify} %}".id}}
        {% relation_class = "::Jennifer::Relation::BelongsTo(#{klass}, #{@type})".id %}
        ::Jennifer::Model::RelationDefinition.declare_dependent({{name}}, {{dependent}}, :belongs_to)

        RELATIONS["{{name.id}}"] =
            {{relation_class}}.new("{{name.id}}", {{foreign}}, {{primary}}, {{klass}}.all{% if request %}.exec {{request}} {% end %})

        @{{name.id}} : {{klass}}?
        @__{{name.id}}_retrieved = false

        def self.{{name.id}}_relation
          RELATIONS["{{name.id}}"].as({{relation_class}})
        end

        def {{name.id}}
          if !@__{{name.id}}_retrieved && @{{name.id}}.nil? && !new_record?
            @__{{name.id}}_retrieved = true
            @{{name.id}} = {{name.id}}_reload
          end
          @{{name.id}}
        end

        def {{name.id}}!
          {{name.id}}.not_nil!
        end

        def {{name.id}}_query
          foreign_field = {{ (foreign ? foreign : "attribute(#{klass}.foreign_key_name)").id }}
          self.class.{{name.id}}_relation.query(foreign_field).as(::Jennifer::QueryBuilder::ModelQuery({{klass}}))
        end

        def {{name.id}}_reload
          @{{name.id}} = {{name.id}}_query.first.as({{klass}}?)
        end

        def append_{{name.id}}(rel : Hash)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = {{klass}}.build(rel, false)
        end

        def append_{{name.id}}(rel : {{klass}})
          @__{{name.id}}_retrieved = true
          @{{name.id}} = rel
        end

        def append_{{name.id}}(rel : Jennifer::Model::Resource)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = rel.as({{klass}})
        end

        def remove_{{name.id}}
          {{@type}}.{{name.id}}_relation.remove(self)
          @{{name.id}} = nil
        end

        def add_{{name.id}}(rel : Hash)
          @{{name.id}} = {{@type}}.{{name.id}}_relation.insert(self, rel)
        end

        def add_{{name.id}}(rel : {{klass}})
          @{{name.id}} = {{@type}}.{{name.id}}_relation.insert(self, rel)
        end
      end

      # Specifies a one-to-one association with another class. This macro should only be used if the other class contains the foreign key.
      # If the current class contains the foreign key, then you should use belongs_to instead.
      macro has_one(name, klass, request = nil, foreign = nil, foreign_type = nil, primary = nil, join_foreign = nil, dependent = :nullify, inverse_of = nil, polymorphic = false)
        {{"{% RELATION_NAMES << #{name.id.stringify} %}".id}}
        ::Jennifer::Model::RelationDefinition.declare_dependent({{name}}, {{dependent}}, :has_one)

        RELATIONS["{{name.id}}"] =
          {% if polymorphic %}
            {% relation_class = "::Jennifer::Relation::PolymorphicHasOne(#{klass}, #{@type})".id %}
            {% if inverse_of.nil? %} {% raise "`inverse_of` is required for a polymorphic has_many relation." %} {% end %}
            {{relation_class}}.new("{{name.id}}", {{foreign}}, {{primary}},
              {{klass}}.all{% if request %}.exec {{request}} {% end %}, foreign_type: {{foreign_type}}, inverse_of: {{inverse_of}})
          {% else %}
            {% relation_class = "::Jennifer::Relation::HasOne(#{klass}, #{@type})".id %}
            {{relation_class}}.new("{{name.id}}", {{foreign}}, {{primary}},
            {{klass}}.all{% if request %}.exec {{request}} {% end %})
          {% end %}

        @{{name.id}} : {{klass}}?
        @__{{name.id}}_retrieved = false

        private def set_{{name.id}}_relation(object)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = object
          {% if inverse_of %}
            object.not_nil!.append_{{inverse_of.id}}(self) if object
          {% end %}
        end

        def self.{{name.id}}_relation
          RELATIONS["{{name.id}}"].as({{relation_class}})
        end

        def {{name.id}}
          if !@__{{name.id}}_retrieved && @{{name.id}}.nil? && !new_record?
            set_{{name.id}}_relation({{name.id}}_reload)
          end
          @{{name.id}}
        end

        def {{name.id}}!
          {{name.id}}.not_nil!
        end

        def {{name.id}}_query
          primary_field = {{ (primary ? primary : "primary").id }}
          self.class.{{name.id}}_relation.query(primary_field).as(::Jennifer::QueryBuilder::ModelQuery({{klass}}))
        end

        def {{name.id}}_reload
          @__{{name.id}}_retrieved = true
          @{{name.id}} = {{name.id}}_query.first.as({{klass}}?)
        end

        # ... ; doesn't support `inverse_of` option
        def append_{{name.id}}(rel : Hash)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = {{klass}}.build(rel, false)
        end

        def append_{{name.id}}(rel : {{klass}})
          @__{{name.id}}_retrieved = true
          @{{name.id}} = rel
        end

        def append_{{name.id}}(rel : Jennifer::Model::Resource)
          @__{{name.id}}_retrieved = true
          @{{name.id}} = rel.as({{klass}})
        end

        def remove_{{name.id}}
          {{@type}}.{{name.id}}_relation.remove(self)
          @{{name.id}} = nil
        end

        def add_{{name.id}}(rel : Hash)
          @{{name.id}} = {{@type}}.{{name.id}}_relation.insert(self, rel)
        end

        def add_{{name.id}}(rel : {{klass}})
          @{{name.id}} = {{@type}}.{{name.id}}_relation.insert(self, rel)
        end
      end

      # :nodoc:
      macro inherited_hook
        # :nodoc:
        RELATION_NAMES = [] of String
        # :nodoc:
        RELATIONS = {} of String => ::Jennifer::Relation::IRelation

        {% verbatim do %}
          # :nodoc:
          def append_relation(name : String, hash_or_object)
            {% if !RELATION_NAMES.empty? %}
              case name
              {% for rel in RELATION_NAMES %}
              when {{rel}}
                append_{{rel.id}}(hash_or_object)
              {% end %}
              else
                super(name, hash_or_object)
              end
            {% else %}
              super(name, hash_or_object)
            {% end %}
          end

          # :nodoc:
          def relation_retrieved(name : String)
            {% if !RELATION_NAMES.empty? %}
              case name
              {% for rel in RELATION_NAMES %}
                when {{rel}}
                  @__{{rel.id}}_retrieved = true
              {% end %}
              else
                super(name)
              end
            {% else %}
              super(name)
            {% end %}
          end

          # :nodoc:
          def get_relation(name : String)
            {% relations = RELATION_NAMES %}
            {% if relations.size > 0 %}
              case name
              {% for rel in relations %}
                when {{rel}}
                  {{rel.id}}
              {% end %}
              else
                super(name)
              end
            {% else %}
              super(name)
            {% end %}
          end

          protected def __refresh_relation_retrieves
            {% for rel in RELATION_NAMES %}
              @__{{rel.id}}_retrieved = false
            {% end %}
            super
          end
        {% end %}
      end
    end
  end
end
