The emon file, ususally is stored with *.dat format, it's it's a ASCII text file, with very long lines. In this emon file there are system information and lots of event data that captured in one server, including CPU, cache, memory, NUMA, PMU, interconnect, PCIe, and software/toolchain details. 
And for the event data, we have [emon_tool](../emon_tool.sh) to parse the events, the tool parse the emon data to several *.csv file and one *.xlsx file. (For this tool, please understand the script to know how it works then you can handle better when hit issue on this tool)

### The *.csv file format;

    __mpp_b2cmi_uncore_view_summary.csv -> b2cmi_uncore_view
    __mpp_b2cxl_uncore_view_summary.csv -> b2cxl_uncore_view
    __mpp_cha_uncore_view_summary.csv -> cha_uncore_view
    __mpp_chacms_uncore_view_summary.csv -> chacms_uncore_view
    __mpp_cms_uncore_view_summary.csv -> cms_uncore_view
    __mpp_core_view_summary.csv -> core_view
    __mpp_crs_uncore_view_summary.csv -> crs_uncore_view
    __mpp_cxlcm_uncore_view_summary.csv -> cxlcm_uncore_view
    __mpp_cxldp_uncore_view_summary.csv -> cxldp_uncore_view
    __mpp_i_uncore_view_summary.csv -> i_uncore_view
    __mpp_iio_uncore_view_summary.csv -> iio_uncore_view
    __mpp_m_uncore_view_summary.csv -> m_uncore_view
    __mpp_mdf_uncore_view_summary.csv -> mdf_uncore_view
    __mpp_p_uncore_view_summary.csv -> p_uncore_view
    __mpp_socket_view_summary.csv -> socket_view
    __mpp_system_view_details.csv -> system_view
    __mpp_system_view_summary.csv -> system_view
    __mpp_thread_view_summary.csv -> thread_view
    __mpp_u_uncore_view_summary.csv -> u_uncore_view
    __mpp_upi_uncore_view_summary.csv -> upi_uncore_view

### Sheets in the *.xlsx file ;
The *.xlsx file is the overover file that contains all of the data from csv file, including 

    system view
    socket view
    core view
    thread view
    b2cmi uncore view
    b2cxl uncore view
    chacms uncore view
    cha uncore view
    cms uncore view
    crs uncore view
    cxlcm uncore view
    cxldp uncore view
    iio uncore view
    i uncore view
    mdf uncore view
    m uncore view
    p uncore view
    upi uncore view
    u uncore view

## Where to put the files
- You can pull the *.dat file from my server node [emon_data](../emon_data/README.md), create a corresponding folder (you can use the dat file name) to contain the *.dat file, and put the info file in the same folder.  

## permission
- Please don't ask me for permission to install tools if you want install to to parse the emon file. 
- Please don't ask me for permission to modify files in your created folder under [emon_data](../emon_data/README.md), don't touch other folders. 


