class transaction ;
  
  rand bit oper;
  bit wr , rd ;
  bit empty , full ;
  bit [7:0] din ;
  bit [7:0] dout;
  
  constraint OP{oper dist  {1:=50 , 0:=50};}
  
  function void display(input string tag);
    $display("[%s] : wr = %0b , rd = %0b , din = %0d , dout = %0d , empty = %0b , full = %0b" , tag,wr,rd,din,dout,empty,full);
  endfunction
  
endclass

class generator;
  
  mailbox #(transaction) mbx ;
  transaction tr_h;
  event next; // to confirm next transaction to send to driver
  event done; // to indicate the no. of stimulus is sent
  int count = 0 ;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx ;
    tr_h = new();
  endfunction
  
  task run();
    int i=0;
    repeat(count) begin
      assert(tr_h.randomize());
      mbx.put(tr_h);
      i++;
      $display("[GEN] : oper : %0b , iteration : %0d", tr_h.oper , i);
      @(next);
    end
    ->done;
  endtask
  
endclass

class driver ;
  
  transaction tr_h;
  virtual fifo_if vif;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task reset();
  vif.rst <= 1;
  vif.wr <= 0;
  vif.rd <= 0;
  vif.din <= 0;
  repeat(5) @(posedge vif.clk)
  vif.rst <= 0;
  $display("[DRV]: DUT reset done");
  $display("------------------------");
  endtask
  
  task write();
      @(posedge vif.clk);
      vif.rst <= 0;
      vif.wr <= 1 ;
      vif.rd <= 0;
      vif.din <= $urandom_range(1,10);
      @(posedge vif.clk);
      vif.wr <=0;
      $display("[DRV] : Driver wrote into DUT : %0d ", vif.din);
      @(posedge vif.clk);
  endtask
  
  task read();
      @(posedge vif.clk);
      vif.rst <= 0 ;
      vif.rd <= 1 ;
      vif.wr <= 0;
      @(posedge vif.clk);
      vif.rd <=0;
      $display("[DRV] : Driver enabled read in DUT ");
      @(posedge vif.clk);
  endtask
  
  task run();
    forever begin
      mbx.get(tr_h);
    if(tr_h.oper == 1)
      write();
    else 
      read();
    end
  endtask
  
endclass
    
class monitor;
  
  virtual fifo_if vif;
  transaction tr_h;
  mailbox #(transaction) mbx;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task run;
    tr_h = new();
    forever begin
      repeat(2) @(posedge vif.clk);
      tr_h.wr = vif.wr;
      tr_h.rd = vif.rd ;
      tr_h.din = vif.din;
      tr_h.full = vif.full;
      tr_h.empty = vif.empty;
      @(posedge vif.clk);
      tr_h.dout = vif.dout;
      $display("[MON] : wr = %0b , rd = %0b , din = %0d , dout = %0d , empty = %0b , full = %0b" ,tr_h.wr, tr_h.rd, tr_h.din, tr_h.dout, tr_h.empty, tr_h.full);
      mbx.put(tr_h);
    end
  endtask
  
endclass

class scoreboard;
  mailbox #(transaction) mbx;
  transaction tr_h;
  bit [7:0]din[$];
  bit [7:0] temp;
  int err=0;
  event next;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task run;
    forever begin
      mbx.get(tr_h);
      tr_h.display("SCO");
      
      if(tr_h.wr==1)
        begin
        if(tr_h.full ==0) 
          begin
          din.push_front(tr_h.din);
            $display("[SCO] : Data stored in queue : %0d ", tr_h.din );
          end
        else
        begin
        $display("FIFO is full!");
        end
        $display("-----------------------------");
        end
      
      
      if(tr_h.rd == 1) begin
        if(tr_h.empty == 0) begin
        temp = din.pop_back();
          
        if(temp == tr_h.dout)
         
           $display("[SCO] : Data Matched !");
         
        else begin
          $error("[SCO] : Data Mismatch ! ");
          err++;
        end
      end
        
        else begin
          $display("[SCO] : FIFO is empty");
        end
        $display("-----------------------------");
        end
        -> next;
        end
  endtask
  
endclass

class environment;
  
  mailbox #(transaction) mbx1 ;
  mailbox #(transaction) mbx2 ;
  
  generator gen_h;
  driver drv_h;
  monitor mon_h;
  scoreboard sb_h;
  
  virtual fifo_if vif;
  
  event nextgs;
  
  function new (virtual fifo_if vif);
    
    mbx1 = new();
    mbx2 = new();
    
    gen_h = new(mbx1);
    drv_h = new(mbx1);
    
    mon_h = new(mbx2);
    sb_h = new(mbx2);
    
    this.vif = vif;
    drv_h.vif = this.vif;
    mon_h.vif = this.vif ;
    
    gen_h.next = nextgs;
    sb_h.next = nextgs;
    
  endfunction
  
  task pre_test();
    drv_h.reset();
  endtask
  
  task test();
    fork 
      gen_h.run();
      drv_h.run();
      mon_h.run();
      sb_h.run();
    join_any
  endtask
  
  task post_test();
    wait(gen_h.done.triggered);
    $display("error count : %0d", sb_h.err);
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
endclass
 
module tb;
  
  fifo_if fif();
  FIFO dut(.clk(fif.clk) , .rst(fif.rst) , .wr(fif.wr) , .rd(fif.rd) , .din(fif.din) , .dout(fif.dout) , .empty(fif.empty) , .full(fif.full));
  
  initial begin 
    fif.clk <= 0;
  end
  
  always #10 fif.clk <= ~fif.clk ;
  
  environment env_h;
  
  initial begin
    env_h = new(fif);
    env_h.gen_h.count = 30;
    env_h.run();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars();
  end
  
endmodule
  
