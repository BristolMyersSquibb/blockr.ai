#' @rdname new_llm_block
#' @export
llm_block_ui <- function(x) {
  UseMethod("llm_block_ui", x)
}

#' @rdname new_llm_block
#' @export
llm_block_ui.llm_block_proxy <- function(x) {
  function(id) {
    tagList(
      shinyjs::useShinyjs(),
      # Styling and JavaScript
      tags$style(HTML(llm_block_css(x))),
      if (isTRUE(x[["enable_image_upload"]])) {
        tags$script(HTML(image_upload_js(id)))
      } else {
        NULL
      },
      div(
        class = "llm-block",
        # Question input section
        textAreaInput(
          NS(id, "question"),
          "Question",
          value = x[["question"]],
          rows = 3,
          width = "100%",
          resize = "vertical"
        ),

        # Image upload section (conditional)
        if (isTRUE(x[["enable_image_upload"]])) {
          div(
            class = "image-upload-section",
            style = "margin: 10px 0; padding: 10px; border: 1px dashed #ccc; border-radius: 5px;",
            fileInput(
              NS(id, "image_upload"),
              "Upload Image (Optional)",
              accept = ".png,.jpg,.jpeg,.webp,.gif",
              width = "100%"
            ),
            div(
              id = NS(id, "image_preview"),
              style = "margin-top: 10px; display: none;",
              img(
                id = NS(id, "preview_img"),
                style = "max-width: 200px; max-height: 150px; border: 1px solid #ddd;"
              ),
              div(
                style = "margin-top: 5px;",
                actionButton(
                  NS(id, "remove_image"),
                  "Remove Image",
                  class = "btn-sm btn-outline-secondary"
                )
              )
            ),
            div(
              style = "font-size: 0.8em; color: #666; margin-top: 5px;",
              "Supported formats: PNG, JPEG, WebP, GIF."
            )
          )
        },

        # Controls section
        div(
          style = "display: flex; gap: 10px; align-items: center;",
          actionButton(
            NS(id, "ask"),
            "Ask",
            class = "btn-primary"
          )
        ),

        # Progress indicator
        div(
          class = "llm-progress",
          id = NS(id, "progress_container"),
          div(
            class = "progress",
            div(
              class = "progress-bar progress-bar-striped active",
              role = "progressbar",
              style = "width: 100%"
            )
          ),
          p("Thinking...", style = "text-align: center; color: #666;")
        ),

        conditionalPanel(
          condition = sprintf(
            "output['%s'] == true",
            NS(id, "result_is_available")
          ),
          # Response section
          div(
            class = "llm-response",
            # Explanation details
            tags$details(
              class = "llm-details",
              tags$summary("Explanation"),
              div(
                style = "padding: 10px;",
                htmlOutput(NS(id, "explanation"))
              )
            ),

            # Code details
            tags$details(
              class = "llm-details",
              tags$summary("Generated Code"),
              shinyAce::aceEditor(
                NS(id, "code_editor"),
                mode = "r",
                value = style_code(x[["code"]]),
                showPrintMargin = FALSE,
                height = "200px"
              ),
              uiOutput(NS(id, "code_display"))
            )
          )
        )
      )
    )
  }
}

#' JavaScript for image upload functionality
#' @param id Module namespace id
image_upload_js <- function(id) {
  sprintf("
    $(document).ready(function() {
      var fileInputId = '#%s-image_upload';
      var previewId = '#%s-image_preview';
      var imgId = '#%s-preview_img';
      var removeId = '#%s-remove_image';
      
      // File input change handler
      $(fileInputId).on('change', function(e) {
        var file = e.target.files[0];
        if (file) {
          showImagePreview(file);
        }
      });
      
      // Remove image handler
      $(removeId).on('click', function() {
        $(fileInputId).val('');
        $(previewId).hide();
      });
      
      function showImagePreview(file) {
        var reader = new FileReader();
        reader.onload = function(e) {
          $(imgId).attr('src', e.target.result);
          $(previewId).show();
        };
        reader.readAsDataURL(file);
      }
    });
  ", id, id, id, id)
}
