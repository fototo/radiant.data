############################################
## Pivotr - combination of Explore and View
############################################

pvt_normalize <- c("None" = "None", "Row" = "row", "Column" = "column",
                   "Total" = "total")
pvt_format <- c("None" = "none", "Color bar" = "color_bar", "Heat map" = "heat")
pvt_type <- c("Dodge" = "dodge","Fill" = "fill")

## UI-elements for pivotr
output$ui_pvt_cvars <- renderUI({

  withProgress(message = "Acquiring variable information", value = 1, {
    vars <- groupable_vars()
  })
  req(available(vars))

  isolate({
    ## if nothing is selected pvt_cvars is also null
    if ("pvt_cvars" %in% names(input) && is.null(input$pvt_cvars)) {
      r_state$pvt_cvars <<- NULL
    } else {
      if (available(r_state$pvt_cvars) && all(r_state$pvt_cvars %in% vars)) {
        vars <- unique(c(r_state$pvt_cvars, vars))
        names(vars) <- varnames() %>% {.[match(vars, .)]} %>% names
      }
    }
  })

  selectizeInput("pvt_cvars", label = "Categorical variables:", choices = vars,
    selected = state_multiple("pvt_cvars", vars),
    multiple = TRUE,
    options = list(placeholder = 'Select categorical variables',
                   plugins = list('remove_button', 'drag_drop'))
  )
})

output$ui_pvt_nvar <- renderUI({
  isNum <- .getclass() %in% c("integer","numeric","factor","logical")
  vars <- c("None", varnames()[isNum])

  if (any(vars %in% input$pvt_cvars)) {
    vars <- setdiff(vars, input$pvt_cvars)
    names(vars) <- varnames() %>% {.[which(. %in% vars)]} %>% {c("None",names(.))}
  }

  selectizeInput("pvt_nvar", label = "Numeric variable:", choices = vars,
    selected = state_single("pvt_nvar", vars, "None"),
    multiple = FALSE, options = list(placeholder = 'Select numeric variable'))
})

output$ui_pvt_fun <- renderUI({
  r_funs <- getOption("radiant.functions")
  selectizeInput("pvt_fun", label = "Apply function:",
                 choices = r_funs,
                 selected = state_single("pvt_fun", r_funs, "mean_rm"),
                 multiple = FALSE)
})

output$ui_pvt_normalize  <- renderUI({
  if (!is.null(input$pvt_cvars) && length(input$pvt_cvars) == 1)
    pvt_normalize <- pvt_normalize[-(2:3)]

  selectizeInput("pvt_normalize", label = "Normalize by:",
    choices = pvt_normalize,
    selected = state_single("pvt_normalize", pvt_normalize, "None"),
    multiple = FALSE)
})

output$ui_pvt_format  <- renderUI({
  selectizeInput("pvt_format", label = "Conditional formatting:",
    choices = pvt_format,
    selected = state_single("pvt_format", pvt_format, "none"),
    multiple = FALSE)
})

output$ui_Pivotr <- renderUI({
  tagList(
    wellPanel(
      checkboxInput("pvt_pause", "Pause pivot", state_init("pvt_pause", FALSE)),
      uiOutput("ui_pvt_cvars"),
      uiOutput("ui_pvt_nvar"),
      conditionalPanel("input.pvt_nvar != 'None'", uiOutput("ui_pvt_fun")),
      uiOutput("ui_pvt_normalize"),
      uiOutput("ui_pvt_format"),
      numericInput("pvt_dec", label = "Decimals:",
                   value = state_init("pvt_dec", 3), min = 0),
      with(tags, table(
        tr(
          td(checkboxInput("pvt_tab", "Show table  ", value = state_init("pvt_tab", TRUE))),
          td(HTML("&nbsp;&nbsp;")),
          td(checkboxInput("pvt_plot", "Show plot  ", value = state_init("pvt_plot", FALSE)))
        ),
        tr(
          td(checkboxInput("pvt_perc", "Percentage", value = state_init("pvt_perc", FALSE))),
          td(HTML("&nbsp;&nbsp;")),
          td(conditionalPanel("input.pvt_nvar == 'None'",
               checkboxInput("pvt_chi2", "Chi-square", value = state_init("pvt_chi2", FALSE))))
      )))
    ),
    conditionalPanel("input.pvt_plot == true",
      wellPanel(
        radioButtons("pvt_type", label = "Plot type:",
          pvt_type,
          selected = state_init("pvt_type", "dodge"),
          inline = TRUE),
        checkboxInput("pvt_flip", "Flip", value = state_init("pvt_flip", FALSE))
      )
    ),
    wellPanel(
      tags$table(
        tags$td(textInput("pvt_dat", "Store as:", paste0(input$dataset,"_pvt"))),
        tags$td(actionButton("pvt_store", "Store"), style = "padding-top:30px;")
      )
    ),
    help_and_report(modal_title = "Pivotr",
                    fun_name = "pivotr",
                    help_file = inclMD(file.path(getOption("radiant.path.data"),"app/tools/help/pivotr.md")))
  )
})

pvt_args <- as.list(formals(pivotr))

observeEvent(input$pvt_nvar, {
  ## only allow chi2 if frequencies are shown
  if (input$pvt_nvar != "None")
    updateCheckboxInput(session, "pvt_chi2", value = FALSE)
})

## list of function inputs selected by user
pvt_inputs <- reactive({
  ## loop needed because reactive values don't allow single bracket indexing
  pvt_args$data_filter <- if (input$show_filter) input$data_filter else ""
  pvt_args$dataset <- input$dataset
  for (i in r_drop(names(pvt_args)))
    pvt_args[[i]] <- input[[paste0("pvt_",i)]]

  pvt_args
})

pvt_sum_args <- as.list(if (exists("summary.pivotr")) formals(summary.pivotr)
                        else formals(radiant.data:::summary.pivotr))

## list of function inputs selected by user
pvt_sum_inputs <- reactive({
  ## loop needed because reactive values don't allow single bracket indexing
  for (i in names(pvt_sum_args))
    pvt_sum_args[[i]] <- input[[paste0("pvt_",i)]]
  pvt_sum_args
})

pvt_plot_args <- as.list(if (exists("plot.pivotr")) formals(plot.pivotr)
                         else formals(radiant.data:::plot.pivotr))

## list of function inputs selected by user
pvt_plot_inputs <- reactive({
  ## loop needed because reactive values don't allow single bracket indexing
  for (i in names(pvt_plot_args))
    pvt_plot_args[[i]] <- input[[paste0("pvt_",i)]]
  pvt_plot_args
})

.pivotr <- reactive({
  req(available(input$pvt_cvars))
  req(!any(input$pvt_nvar %in% input$pvt_cvars))

  pvti <- pvt_inputs()
  if (is_empty(input$pvt_fun)) pvti$fun <- "length"
  if (is_empty(input$pvt_nvar)) pvti$nvar <- "None"

  if (!is_empty(pvti$nvar, "None"))
    req(available(pvti$nvar))

  req(input$pvt_pause == FALSE, cancelOutput = TRUE)

  withProgress(message = "Calculating", value = 1, {
    sshhr( do.call(pivotr, pvti) )
  })
})

observeEvent(input$pivotr_search_columns, {
  r_state$pivotr_search_columns <<- input$pivotr_search_columns
})

observeEvent(input$pivotr_state, {
  r_state$pivotr_state <<-
    if (is.null(input$pivotr_state)) list() else input$pivotr_state
})

output$pivotr <- DT::renderDataTable({
  pvt <- .pivotr()
  if (is.null(pvt)) return(data.frame())

  if (!identical(r_state$pvt_cvars, input$pvt_cvars)) {
    r_state$pvt_cvars <<- input$pvt_cvars
    r_state$pivotr_state <<- list()
    r_state$pivotr_search_columns <<- rep("", ncol(pvt$tab))
  }

  searchCols <- lapply(r_state$pivotr_search_columns, function(x) list(search = x))
  order <- r_state$pivotr_state$order
  pageLength <- r_state$pivotr_state$length

  withProgress(message = 'Generating pivot table', value = 1,
    dtab(pvt, format = input$pvt_format, perc = input$pvt_perc,
            dec = input$pvt_dec, searchCols = searchCols, order = order,
            pageLength = pageLength)
  )

})

output$pivotr_chi2 <- renderPrint({
  req(input$pvt_chi2)
  req(input$pvt_dec)
  .pivotr() %>% {if (is.null(.)) return(invisible())
                 else summary(., chi2 = TRUE, dec = input$pvt_dec, shiny = TRUE)}
})

output$dl_pivot_tab <- downloadHandler(
  filename = function() { paste0("pivot_tab.csv") },
  content = function(file) {
    dat <- .pivotr()
    if (is.null(dat)) {
      write.csv(data_frame("Data" = "[Empty]"),file, row.names = FALSE)
    } else {
      rows <- isolate(r_data$pvt_rows)
      dat$tab %>% {if (is.null(rows)) . else .[c(rows,nrow(.)),, drop = FALSE]} %>%
        write.csv(file, row.names = FALSE)
    }
  }
)

pvt_plot_width <- function() 750
pvt_plot_height <- function() {
   pvt <- .pivotr()
   if (is.null(pvt)) return(400)
   pvt %<>% pvt_sorter(rows = r_data$pvt_rows)
   if (length(input$pvt_cvars) > 2) {
       pvt$tab %>% .[[input$pvt_cvars[3]]] %>%
         levels %>%
         length %>% {. * 200}
   } else if (input$pvt_flip) {
      if (length(input$pvt_cvars) == 2)
        max(400, ncol(pvt$tab) * 15)
      else
        max(400, nrow(pvt$tab) * 15)
   } else {
      400
   }
}

pvt_sorter <- function(pvt, rows = NULL) {
  if (is.null(rows)) return(pvt)
  cvars <- pvt$cvars
  tab <- pvt$tab %>% {filter(., .[[1]] != "Total")}

  if (length(cvars) > 1)
    tab %<>% select(-which(colnames(.) == "Total"))

  tab <- tab[rows,, drop = FALSE]
  cvars <- if (length(cvars) == 1) cvars else cvars[-1]

  ## order factors as set in the sorted data
  for (i in cvars)
    tab[[i]] %<>% factor(., levels = unique(.))

  pvt$tab <- tab
  pvt
}

observeEvent(input$pivotr_rows_all, {
  dt_rows <- input$pivotr_rows_all
  if (identical(r_data$pvt_rows, dt_rows)) return()
  r_data$pvt_rows <- dt_rows
})

.plot_pivot <- reactive({
  pvt <- .pivotr()

  if (is.null(pvt)) return(invisible())
  if (!is_empty(input$pvt_tab, FALSE))
    pvt <- pvt_sorter(pvt, rows = r_data$pvt_rows)
    pvt_plot_inputs() %>% { do.call(plot, c(list(x = pvt), .)) }
})

output$plot_pivot <- renderPlot({
  if (is_empty(input$pvt_plot, FALSE)) return(invisible())
  withProgress(message = 'Making plot', value = 1, {
    sshhr(.plot_pivot()) %>% print
  })
  return(invisible())
}, width = pvt_plot_width, height = pvt_plot_height, res = 96)

observeEvent(input$pvt_store, {
  dat <- .pivotr()
  if (is.null(dat)) return()
  name <- input$pvt_dat
  rows <- input$pivotr_rows_all
  dat$tab %<>% {if (is.null(rows)) . else .[rows,, drop = FALSE]}
  store(dat, name)
  updateSelectInput(session, "dataset", selected = input$dataset)

  ## alert user about new dataset
  session$sendCustomMessage(type = "message",
    message = paste0("Dataset '", name, "' was successfully added to the datasets dropdown. Add code to R > Report to (re)create the results by clicking the report icon on the bottom left of your screen.")
  )
})

observeEvent(input$pivotr_report, {

  inp_out <- list("","")
  inp_out[[1]] <- clean_args(pvt_sum_inputs(), pvt_sum_args[-1])

  if (input$pvt_plot == TRUE) {
    inp_out[[2]] <- clean_args(pvt_plot_inputs(), pvt_plot_args[-1])
    outputs <- c("summary","plot")
    figs <- TRUE
  } else {
    outputs <- c("summary")
    figs <- FALSE
  }

  ## get the state of the dt table
  ts <- dt_state("pivotr")
  xcmd <- paste0("#dtab(result")
  if (!is_empty(input$pvt_format, "none"))
    xcmd <- paste0(xcmd, ", format = \"", input$pvt_format, "\"")
  if (isTRUE(input$pvt_perc))
    xcmd <- paste0(xcmd, ", perc = ", input$pvt_perc)
  if (!is_empty(input$pvt_dec, 3))
    xcmd <- paste0(xcmd, ", dec = ", input$pvt_dec)
  if (!is_empty(r_state$pivotr_state$length, 10))
    xcmd <- paste0(xcmd, ", pageLength = ", r_state$pivotr_state$length)
  xcmd <- paste0(xcmd, ") %>% render\n#store(result, name = \"", input$pvt_dat, "\")")

  inp_main <- clean_args(pvt_inputs(), pvt_args)
  if (ts$tabsort != "") inp_main <- c(inp_main, tabsort = ts$tabsort)
  if (ts$tabfilt != "") inp_main <- c(inp_main, tabfilt = ts$tabfilt)
  inp_main <- c(inp_main, nr = ts$nr - 1)

  ## update R > Report
  update_report(inp_main = inp_main,
                fun_name = "pivotr",
                outputs = outputs,
                inp_out = inp_out,
                figs = figs,
                fig.width = pvt_plot_width(),
                fig.height = pvt_plot_height(),
                xcmd = xcmd)
})
