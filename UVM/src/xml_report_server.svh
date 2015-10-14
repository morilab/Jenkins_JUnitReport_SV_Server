//----------------------------------------------------------------------
//   Copyright 2012 Verilab Inc.
//   Gordon McGregor (gordon.mcgregor@verilab.com)
//
//   All Rights Reserved Worldwide
//
//   Licensed under the Apache License, Version 2.0 (the
//   "License"); you may not use this file except in
//   compliance with the License.  You may obtain a copy of
//   the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in
//   writing, software distributed under the License is
//   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
//   CONDITIONS OF ANY KIND, either express or implied.  See
//   the License for the specific language governing
//   permissions and limitations under the License.
//----------------------------------------------------------------------
//   Copyright 2015 MoriLab. modified
//   d.mori (twitter @morittyo)
//
//   Licensed under the Apache License, Version 2.0 ,too.
//
//   - UVM 1.1
//   - Jenkins 1.611
//     + JUnit Plugin 1.5
//----------------------------------------------------------------------

`ifndef __XML_REPORT_SERVER_SVH__
`define __XML_REPORT_SERVER_SVH__

import uvm_pkg::*;
`include "uvm_macros.svh"

class xml_report_server extends uvm_report_server;

  uvm_report_server old_report_server;
  uvm_report_global_server global_server;
  string test_name;
  string suite_name;
  bit use_id_as_class_name;
  bit use_id_as_test_name;
  string class_name;
  string testcase_ng[string]      ; //= {default:"\n"};
  string testcase_message[string] ; //= {default:"\n"};
  integer logfile_handle;

  // characters that are invalid XML that have to be encoded
  string replacements[string] = '{ "<" : "&lt;",
                                   "&" : "&amp;",
                                   ">" : "&gt;",
                                   "'" : "&apos;",
                                   "\"": "&quot;"
                                 };

  /// constructor
  function new(string name,string log_filename = "",string suitename = "",string classname = "",string packagename = "",bit use_id_as_testname = 0);
    super.new();

    test_name = name;
    global_server = new();
    install_server();
    if(log_filename=="")begin
      $swrite(log_filename,"%s.xml",name);
    end
    if(suitename=="")begin
      suite_name = test_name;
    end else begin
      suite_name = suitename;
    end
    if((packagename=="") && (classname==""))begin
      // For backwards compatibility, if neither of these are specified, then use the ID as the class_name (like previously was done)
      use_id_as_class_name = 1;
      class_name = ""; 
    end else if (packagename=="") begin
      use_id_as_class_name = 0;
      class_name = {classname,".",test_name};
    end else if (classname=="") begin
      use_id_as_class_name = 0;
      class_name = {packagename,".",test_name};
    end else begin
      use_id_as_class_name = 0;
      class_name = {packagename,".",classname};
    end
    use_id_as_test_name = use_id_as_testname;
    logfile_handle = $fopen(log_filename, "w");
    report_header(logfile_handle);
  endfunction

  /// replace the global server with this server
  function void install_server;
    old_report_server = global_server.get_server();
    global_server.set_server(this);
  endfunction

  /// Configure all components to use UVM_LOG actions to trigger XML capture
  /// has to be called after components have been instantiated (end of elaboration, run etc)
  function void enable_xml_logging(uvm_component base=null);
    uvm_root top;

    if (base == null) begin
      top = uvm_root::get();
      base = top;
    end

    base.set_report_default_file_hier(logfile_handle);
    base.set_report_severity_action_hier(UVM_INFO,    UVM_DISPLAY | UVM_LOG);
    base.set_report_severity_action_hier(UVM_WARNING, UVM_DISPLAY | UVM_LOG);
    base.set_report_severity_action_hier(UVM_ERROR,   UVM_DISPLAY | UVM_LOG | UVM_COUNT);
    base.set_report_severity_action_hier(UVM_FATAL,   UVM_DISPLAY | UVM_LOG | UVM_EXIT);
  endfunction

  /// Helper function to convert verbosity value to appropriate string, based on uvm_verbosity enum if an equivalent level
  function string convert_verbosity_to_string(int verbosity);
    uvm_verbosity l_verbosity;

    if ($cast(l_verbosity, verbosity)) begin
        convert_verbosity_to_string = l_verbosity.name();
    end else begin
        string l_str;
        l_str.itoa(verbosity);
        convert_verbosity_to_string = l_str;
    end
  endfunction

  /// Output JUnit XML header to log file
  function void report_header(UVM_FILE file = 0);
    string str;
    $swrite(str, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
    $swrite(str, "%s\n<testsuite%s>",str,{xla("name",suite_name)});
    f_display(file,str);
  endfunction

  /// Output JUnit XML closing tags to log file
  function void report_footer(UVM_FILE file = 0);
    integer result;
    string final_classname;
    string final_testname;
    $fflush(file);
    foreach (testcase_message[id])begin
      result = $fseek(logfile_handle, 0, 2);
      if (use_id_as_class_name) begin
        final_classname = id;
      end else begin
        final_classname = class_name;
      end
      if (use_id_as_test_name) begin
        final_testname = id;
      end else begin
        final_testname = test_name;
      end
      f_display(logfile_handle, xle_n("testcase",{testcase_ng[id],xle_n("system-out",testcase_message[id])},{xla("classname",final_classname),xla("name",final_testname)}));
    end
    f_display(logfile_handle, "</testsuite>");
  endfunction

  /// tidy up logging and restore global report server
  function void summarize(UVM_FILE file = 0);
    report_footer();
    global_server.set_server(old_report_server);
    $fclose(logfile_handle);
    old_report_server.summarize(file);
  endfunction

  /// Processes the message's actions.
  virtual function void process_report(
    uvm_severity severity,
    string name,
    string id,
    string message,
    uvm_action action,
    UVM_FILE file,
    string filename,
    int line,
    string composed_message,
    int verbosity_level,
    uvm_report_object client
    );
    // update counts
    incr_severity_count(severity);
    incr_id_count(id);

    if(action & UVM_DISPLAY)
      $display("%s",composed_message);

    // if log is set we need to send to the file but not resend to the
    // display. So, we need to mask off stdout for an mcd or we need
    // to ignore the stdout file handle for a file handle.
    if(action & UVM_LOG)
      if( (file == 0) || (file != 32'h8000_0001) ) //ignore stdout handle
      begin
        UVM_FILE tmp_file = file;
        string str;
        if( (file&32'h8000_0000) == 0) //is an mcd so mask off stdout
        begin
          tmp_file = file & 32'hffff_fffe;
        end
        str = testcase_message[id];
        testcase_message[id] = {str,compose_xml_message(severity, verbosity_level, name, id, message, filename, line)};
      end

    if(action & UVM_EXIT) client.die();

    if(action & UVM_COUNT) begin
      if(get_max_quit_count() != 0) begin
        incr_quit_count();
        if(is_quit_count_reached()) begin
          client.die();
        end
      end
    end

    if (action & UVM_STOP) $stop;

  endfunction

  /// Given an unencoded input string, replaces illegal characters for XML data format
  function string sanitize(string data);

    for(int i = data.len()-1; i >= 0; i--) begin
      if (replacements.exists(data[i])) begin
          data = {data.substr(0,i-1), replacements[data[i]], data.substr(i+1, data.len()-1)};
      end
    end
    return data;
  endfunction : sanitize

  /// XML Attribute
  /// Generate an XML attribute ( tag = "data" )
  function string xla(string tag, string data);
    xla="";
    if (data != "") begin
      xla = {" ", tag, "=\"", sanitize(data), "\" "};
    end
  endfunction

  /// XML Element (data sanitized)
  /// Generate an XML element ( <tag attributes>data</tag> )
  function string xle(string tag, string data, string attributes="");
    xle = xle_n(tag,sanitize(data),attributes);
  endfunction

  /// XML Element
  /// Generate an XML element ( <tag attributes>data</tag> )
  function string xle_n(string tag, string data, string attributes="");
    xle_n = "";
    if (data != "") begin
      xle_n = {"<", tag, attributes, ">", data, "</", tag, ">\n"};
    end
  endfunction

  /// Generate the XML encapsulated report message, for logging
  virtual function string compose_xml_message(
    uvm_severity severity,
    int verbosity,
    string name,
    string id,
    string message,
    string filename,
    int    line
    );
    uvm_severity_type sv;
    string testcase_ng_string;
    string system_out_string;
    string err_message;
    integer result;

    sv = uvm_severity_type'(severity);
    testcase_ng_string = testcase_ng[id];
    $swrite(err_message,"%s %s(%0d) @ %0d: %s[%s]",sv.name(),filename,line,$time,name,id);
    case(sv)
      UVM_INFO    : begin
        if(0 /*verbosity!=UVM_NONE*/ )begin
          return "";
        end
      end
      UVM_WARNING : testcase_ng[id] = {testcase_ng_string,xle("error"  ,sanitize(message),{xla("message",err_message),xla("type",sv.name())})};
      UVM_ERROR   : testcase_ng[id] = {testcase_ng_string,xle("error"  ,sanitize(message),{xla("message",err_message),xla("type",sv.name())})};
      UVM_FATAL   : testcase_ng[id] = {testcase_ng_string,xle("failure",sanitize(message),{xla("message",err_message),xla("type",sv.name())})};
    endcase
    $swrite(compose_xml_message,"<![CDATA[%s %s]]>\n",err_message,message);
  endfunction
endclass
`endif //_XML_REPORT_SERVER_SVH__
