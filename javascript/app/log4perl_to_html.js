$(document).ready(function(){
    
    $("#log_table").DataTable({
        "iDisplayLength": 10,
        "order" : [[0, 'decs']],
        "lengthMenu": [ [10, 25, 50, -1], [10, 25, 50, "All"] ]
    });

    $(".details").mouseover(function(){
        $(this).css("font-size", "large");
    });
    
    $(".details").mouseout(function(){
        $(this).css("font-size", "small");
    });
});