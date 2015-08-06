require 'rails_helper'

RSpec.describe DriverCompliancesController, type: :controller do
  login_admin_as_current_user

  describe "nested on drivers" do
    before do
      @driver = create :driver, provider: @current_user.current_provider
    end

    # This should return the minimal set of attributes required to create a valid
    # DriverCompliance. As you add validations to DriverCompliance, be sure to
    # adjust the attributes here as well.
    let(:valid_attributes) {{
      event: "My Compliance Event",
      due_date: Date.current.to_s
    }}

    let(:invalid_attributes) {{
      event: nil,
      due_date: nil
    }}

    describe "GET #new" do
      it "assigns a new driver_compliance as @driver_compliance" do
        get :new, {driver_id: @driver.to_param}
        expect(assigns(:driver_compliance)).to be_a_new(DriverCompliance)
      end

      it "assigns the driver as @driver" do
        get :new, {driver_id: @driver.to_param}
        expect(assigns(:driver)).to eq(@driver)
      end

      it "sets @driver as the parent object on @driver_compliance" do
        get :new, {driver_id: @driver.to_param}
        expect(assigns(:driver_compliance).driver).to eq(@driver)
      end
    end

    describe "GET #edit" do
      it "assigns the requested driver_compliance as @driver_compliance" do
        driver_compliance = create :driver_compliance, driver: @driver
        get :edit, {:id => driver_compliance.to_param, driver_id: @driver.to_param}
        expect(assigns(:driver_compliance)).to eq(driver_compliance)
      end

      it "assigns the driver as @driver" do
        driver_compliance = create :driver_compliance, driver: @driver
        get :edit, {:id => driver_compliance.to_param, driver_id: @driver.to_param}
        expect(assigns(:driver)).to eq(@driver)
      end

      it "sets @driver as the parent object on @driver_compliance" do
        driver_compliance = create :driver_compliance, driver: @driver
        get :edit, {:id => driver_compliance.to_param, driver_id: @driver.to_param}
        expect(assigns(:driver_compliance).driver).to eq(@driver)
      end
    end

    describe "POST #create" do
      context "with valid params" do
        it "creates a new DriverCompliance" do
          expect {
            post :create, {:driver_compliance => valid_attributes, driver_id: @driver.to_param}
          }.to change(DriverCompliance, :count).by(1)
        end

        it "assigns a newly created driver_compliance as @driver_compliance" do
          post :create, {:driver_compliance => valid_attributes, driver_id: @driver.to_param}
          expect(assigns(:driver_compliance)).to be_a(DriverCompliance)
          expect(assigns(:driver_compliance)).to be_persisted
        end

        it "sets @driver as the parent object on the new driver_compliance" do
          post :create, {:driver_compliance => valid_attributes, driver_id: @driver.to_param}
          expect(assigns(:driver_compliance).driver).to eq(@driver)
        end

        it "redirects back to the driver" do
          post :create, {:driver_compliance => valid_attributes, driver_id: @driver.to_param}
          expect(response).to redirect_to(@driver)
        end

        context "with nested document association attributes" do
          it "creates new document associations" do
            expect {
              post :create, {:driver_compliance => valid_attributes.merge({
                document_associations_attributes: [
                  { document_id: create(:document, documentable: @driver) }
                ]
              }), driver_id: @driver.to_param}
            }.to change(DocumentAssociation, :count).by(1)
          end
        
          it "rejects document associations with blank document ids" do
            expect {
              post :create, {:driver_compliance => valid_attributes.merge({
                document_associations_attributes: [
                  { document_id: create(:document, documentable: @driver) },
                  { document_id: nil }
                ]
              }), driver_id: @driver.to_param}
            }.to change(DocumentAssociation, :count).by(1)
          end
        end
      end

      context "with invalid params" do
        it "assigns a newly created but unsaved driver_compliance as @driver_compliance" do
          post :create, {:driver_compliance => invalid_attributes, driver_id: @driver.to_param}
          expect(assigns(:driver_compliance)).to be_a_new(DriverCompliance)
        end

        it "re-renders the 'new' template" do
          post :create, {:driver_compliance => invalid_attributes, driver_id: @driver.to_param}
          expect(response).to render_template("new")
        end
      end
    end

    describe "PUT #update" do
      context "with valid params" do
        let(:new_attributes) {{
          event: "My New Compliance Event",
        }}

        it "updates the requested driver_compliance" do
          driver_compliance = create :driver_compliance, driver: @driver
          put :update, {:id => driver_compliance.to_param, :driver_compliance => new_attributes, driver_id: @driver.to_param}
          driver_compliance.reload
          expect(driver_compliance.event).to eq("My New Compliance Event")
        end

        it "assigns the requested driver_compliance as @driver_compliance" do
          driver_compliance = create :driver_compliance, driver: @driver
          put :update, {:id => driver_compliance.to_param, :driver_compliance => valid_attributes, driver_id: @driver.to_param}
          expect(assigns(:driver_compliance)).to eq(driver_compliance)
        end

        it "redirects back to the driver" do
          driver_compliance = create :driver_compliance, driver: @driver
          put :update, {:id => driver_compliance.to_param, :driver_compliance => valid_attributes, driver_id: @driver.to_param}
          expect(response).to redirect_to(@driver)
        end

        context "with nested document association attributes" do
          before do
            @driver_compliance = create :driver_compliance, driver: @driver
            @document_association = create :document_association, document: create(:document, documentable: @driver), associable: @driver_compliance
          end
          
          it "updates document associations" do
            new_document = create :document, documentable: @driver
            expect {
              put :update, {:id => @driver_compliance.to_param, :driver_compliance => valid_attributes.merge({
                document_associations_attributes: [
                  @document_association.attributes.merge({document_id: new_document.id})
                ]
              }), driver_id: @driver.to_param}
            }.to change{ @document_association.reload.document_id }.to(new_document.id)
          end
        
          it "allows new document associations to be added" do
            expect {
              put :update, {:id => @driver_compliance.to_param, :driver_compliance => valid_attributes.merge({
                document_associations_attributes: [
                  { document_id: create(:document, documentable: @driver) }
                ]
              }), driver_id: @driver.to_param}
            }.to change(DocumentAssociation, :count).by(1)
          end
        
          it "allows document associations to be destroyed" do
            expect {
              put :update, {:id => @driver_compliance.to_param, :driver_compliance => valid_attributes.merge({
                document_associations_attributes: [
                  @document_association.attributes.merge({:_destroy => "1"})
                ]
              }), driver_id: @driver.to_param}
            }.to change(DocumentAssociation, :count).by(-1)
          end
        end
      end

      context "with invalid params" do
        it "assigns the driver_compliance as @driver_compliance" do
          driver_compliance = create :driver_compliance, driver: @driver
          put :update, {:id => driver_compliance.to_param, :driver_compliance => invalid_attributes, driver_id: @driver.to_param}
          expect(assigns(:driver_compliance)).to eq(driver_compliance)
        end

        it "re-renders the 'edit' template" do
          driver_compliance = create :driver_compliance, driver: @driver
          put :update, {:id => driver_compliance.to_param, :driver_compliance => invalid_attributes, driver_id: @driver.to_param}
          expect(response).to render_template("edit")
        end
      end
    end

    describe "DELETE #destroy" do
      it "destroys the requested driver_compliance" do
        driver_compliance = create :driver_compliance, driver: @driver
        expect {
          delete :destroy, {:id => driver_compliance.to_param, driver_id: @driver.to_param}
        }.to change(DriverCompliance, :count).by(-1)
      end

      it "redirects back to the driver" do
        driver_compliance = create :driver_compliance, driver: @driver
        delete :destroy, {:id => driver_compliance.to_param, driver_id: @driver.to_param}
        expect(response).to redirect_to(@driver)
      end
    end
  end
end
