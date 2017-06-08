module DocumentAssociableController

  def model_instance
    self.instance_variable_get('@' + self.class.controller_name.classify.underscore)
  end
  
  # Builds new associated documents from params
  def build_new_documents(params)
    # Build new documents as appropriate
    params[:documents_attributes].each do |i, doc|
      unless doc[:id].present?
        if doc[:document].present? && doc[:description].present? && doc[:_destroy].to_i.zero?      
          model_instance.build_document(
            document: doc[:document], 
            description: doc[:description]
          )
        end
        params[:documents_attributes].delete(i)
      end
    end
    
    return params
  end
  
  # returns a list of documents attributes for safe params
  def documents_attributes
    [:id, :document, :description, :_destroy]
  end
  
end
