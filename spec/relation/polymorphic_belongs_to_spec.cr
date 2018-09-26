require "../spec_helper"

describe Jennifer::Relation::IPolymorphicBelongsTo do
  example_class = NoteWithCallback::NotableRelation
  relation_name = "notable"
  note = NoteWithCallback
  profile = FacebookProfileWithDestroyNotable
  example_relation = example_class.new(relation_name, nil, nil, nil)

  describe "#foreign_type" do
    context "without specified foreign type" do
      it do
        example_class.new(relation_name, nil, nil, nil).foreign_type.should eq("notable_type")
      end
    end

    context "with specified foreign type" do
      it do
        example_class.new(relation_name, nil, nil, "specific_type").foreign_type.should eq("specific_type")
      end
    end
  end

  describe "#foreign_field" do
    context "without specified foreign field" do
      it do
        example_class.new(relation_name, nil, nil, nil).foreign_field.should eq("notable_id")
      end
    end

    context "with specified foreign field" do
      it do
        example_class.new(relation_name, "specific_type", nil, nil).foreign_field.should eq("specific_type")
      end
    end
  end

  describe "#primary_field" do
    context "without specified primary field" do
      it do
        example_class.new(relation_name, nil, nil, nil).primary_field.should eq("id")
      end
    end

    context "with specified primary field" do
      it do
        example_class.new(relation_name, nil, "specific_type", nil).primary_field.should eq("specific_type")
      end
    end
  end

  describe "#condition_clause" do
    context "without custom query" do
      describe "for specific id" do
        it do
          condition = example_relation.condition_clause(1, profile.to_s)
          condition.should eq(profile.c(:id, relation_name) == 1)
        end
      end
    end
  end

  describe "#query" do
    context "with nil polymorphic type" do
      it do
        example_relation.query(1, nil).do_nothing?.should be_true
      end
    end

    context "with valid polymorphic type" do
      it do
        p = Factory.create_facebook_profile
        example_relation.query(p.id, profile.to_s).count.should eq(1)
      end
    end

    context "with custom query" do
      it do
        condition = Note::NotableRelation.new(relation_name, nil, nil, nil).query(1, "User").tree
        condition.should eq((User.c(:id, relation_name) == 1) & (User.c(:name).like("%on")))
      end
    end
  end

  describe "#build" do
    context "with valid polymorphic type" do
      it do
        p = example_relation.build({ "login" => "login", "type" => "type" } of String => Jennifer::DBAny, profile.to_s)
        p.is_a?(FacebookProfileWithDestroyNotable).should be_true
        u = example_relation.build({} of String => Jennifer::DBAny, "User")
        u.is_a?(User).should be_true
      end
    end

    context "with invalid polymorphic type" do
      it do
        expect_raises(Jennifer::BaseException) do
          example_relation.build({} of String => Jennifer::DBAny, "Contact")
        end
      end
    end
  end

  describe "#create!" do
    context "with valid polymorphic type" do
      it do
        p = example_relation.create!({ "login" => "login", "type" => "type" } of String => Jennifer::DBAny, profile.to_s)
        p.is_a?(FacebookProfileWithDestroyNotable).should be_true
        p.persisted?.should be_true

        u = example_relation.build(Factory.build_user.to_str_h, "User")
        u.is_a?(User).should be_true
        u.persisted?.should be_true
      end
    end

    context "with invalid polymorphic type" do
      it do
        expect_raises(Jennifer::BaseException) do
          example_relation.create!({} of String => Jennifer::DBAny, "Contact")
        end
      end
    end

    context "with invalid model options" do
      it do
        expect_raises(Jennifer::RecordInvalid) do
          example_relation.create!({} of String => Jennifer::DBAny, "User")
        end
      end
    end
  end

  describe "#load" do
    context "with valid polymorphic type" do
      context "with blank foreign field" do
        it do
          example_relation.load(nil, "User").should be_nil
        end
      end

      it do
        u = Factory.create_user([:with_valid_password])
        example_relation.load(u.id, "User").as(User).id.should eq(u.id)
      end
    end

    context "with invalid polymorphic type" do
      it do
        expect_raises(Jennifer::BaseException) do
          example_relation.load(1, "Contact")
        end
      end
    end
  end

  describe "#destroy" do
    context "with valid polymorphic type" do
      context "with blank foreign field" do
        it do
          n = note.build(text: "test")
          example_relation.destroy(n).should be_nil
        end
      end

      it do
        p = Factory.create_facebook_profile
        n = note.build(text: "test", notable_type: profile.to_s, notable_id: p.id)

        count = profile.destroy_counter
        example_relation.destroy(n)
        profile.find(p.id).should be_nil
        profile.destroy_counter.should eq(count + 1)
      end
    end

    context "with invalid polymorphic type" do
      it do
        n = note.build(text: "test", notable_type: "Contact", notable_id: 1)
        expect_raises(Jennifer::BaseException) do
          example_relation.destroy(n)
        end
      end
    end
  end

  describe "#insert" do
    context "with hash" do
      it do
        n = note.find!(Factory.create_note.id)
        opts = {
          "login" => "login",
          "type" => "type",
          "notable_type" => "FacebookProfileWithDestroyNotable"
        } of String => Jennifer::DBAny
        example_relation.insert(n, opts).as(FacebookProfileWithDestroyNotable)
        p = n.notable.as(FacebookProfileWithDestroyNotable)
        n.notable_id.should eq(p.id)
        n.notable_type.should eq(profile.to_s)
      end
    end

    context "with object" do
      it do
        n = note.find!(Factory.create_note.id)
        p = profile.create!(login: "login", type: "type")
        example_relation.insert(n, p)
        n.notable_id.should eq(p.id)
        n.notable_type.should eq(profile.to_s)
      end

      it "raises exception if object is already assigned" do
        p1 = profile.find!(Factory.create_facebook_profile.id)
        p2 = profile.find!(Factory.create_facebook_profile.id)
        n = note.build(text: "some text")
        n = p2.add_notes(n)[0]
        expect_raises(Jennifer::BaseException) do
          example_relation.insert(n, p1)
        end
      end
    end
  end

  describe "#remove" do
    it do
      p = profile.find!(Factory.create_facebook_profile.id)
      n = p.add_notes(note.build(text: "some text"))[0]

      example_relation.remove(n)
      n.reload
      n.notable_type.should be_nil
      n.notable_id.should be_nil
    end
  end
end
